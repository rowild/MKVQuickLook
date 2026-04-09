import AppKit
import Quartz

final class PreviewViewController: NSViewController, QLPreviewingController {
    private static let minimumExpandedPreviewSize = NSSize(width: 720, height: 440)
    private static let expandedPreferredContentSize = NSSize(width: 960, height: 600)
    private static let compactPreferredContentSize = NSSize(width: 260, height: 120)

    private let previewContentView = PreviewContentView()
    private var player: MediaPreviewPlayer?
    private var currentFileURL: URL?
    private var isMediaLoaded = false
    private var presentationMode: PreviewPresentationMode?

    override func loadView() {
        view = previewContentView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = Self.expandedPreferredContentSize
        previewContentView.playbackToggleHandler = { [weak self] in
            guard let self, let player = self.player else {
                return
            }

            MediaPreviewPlayerSession.activate(player)
            player.togglePlayback()
        }
        previewContentView.seekTrackingHandler = { [weak self] isTracking, interactionID in
            guard let self else {
                return
            }

            if isTracking {
                PlaybackDiagnostics.log("[seek] controller-begin id=\(interactionID) t=\(PlaybackDiagnostics.timestampString())")
                self.player?.beginScrubbing(interactionID: interactionID)
            } else {
                PlaybackDiagnostics.log("[seek] controller-end id=\(interactionID) t=\(PlaybackDiagnostics.timestampString())")
                self.player?.endScrubbing(interactionID: interactionID)
            }
        }
        previewContentView.seekHandler = { [weak self] position, isFinal, interactionID in
            PlaybackDiagnostics.log("[seek] controller-change id=\(interactionID ?? 0) position=\(String(format: "%.4f", position)) final=\(isFinal) t=\(PlaybackDiagnostics.timestampString())")
            self?.player?.seek(to: position, isFinal: isFinal, interactionID: interactionID)
        }
        previewContentView.volumeHandler = { [weak self] volume, interactionID in
            PlaybackDiagnostics.log("[volume] controller-change id=\(interactionID) target=\(volume) t=\(PlaybackDiagnostics.timestampString())")
            self?.player?.setVolume(volume, interactionID: interactionID)
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        player?.refreshVideoLayout()
        updatePresentationModeAndPlayback()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        player?.stop()
        MediaPreviewPlayerSession.deactivate(player)
        isMediaLoaded = false
    }

    func preparePreviewOfFile(at url: URL) async throws {
        do {
            MediaPreviewPlayerSession.stopActivePreview()
            let metadata = try PreviewMetadata(fileURL: url)
            let player = VLCKitMediaPreviewPlayer()
            player.playbackStateDidChange = { [weak self] state in
                self?.previewContentView.updatePlaybackState(state)
            }
            player.playbackMetricsDidChange = { [weak self] metrics in
                self?.previewContentView.updatePlaybackMetrics(metrics)
            }
            player.videoPresentationSizeDidChange = { [weak self] size in
                self?.previewContentView.updateVideoPresentationSize(size)
            }
            player.videoOutputVisibilityDidChange = { [weak self] isVisible in
                self?.previewContentView.setVideoOutputVisible(isVisible)
            }

            self.player = MediaPreviewPlayerSession.replace(current: self.player, with: player)

            await MainActor.run {
                title = metadata.displayName
                previewContentView.apply(metadata: metadata)
                previewContentView.attachRenderView(player.renderView)
            }

            currentFileURL = url
            isMediaLoaded = false
            updatePresentationModeAndPlayback()
        } catch {
            await MainActor.run {
                title = url.lastPathComponent
                previewContentView.apply(error: error.localizedDescription)
            }
            throw error
        }
    }

    private func updatePresentationModeAndPlayback() {
        let mode = currentPresentationMode()
        let modeChanged = presentationMode != mode
        presentationMode = mode

        previewContentView.setPresentationMode(mode)
        preferredContentSize = mode == .expanded ? Self.expandedPreferredContentSize : Self.compactPreferredContentSize

        switch mode {
        case .compact:
            if isMediaLoaded && modeChanged {
                player?.stop()
                MediaPreviewPlayerSession.deactivate(player)
                isMediaLoaded = false
            }
        case .expanded:
            if !isMediaLoaded, let currentFileURL {
                player?.loadMedia(from: currentFileURL)
                isMediaLoaded = true
                if let player {
                    MediaPreviewPlayerSession.activate(player)
                    player.play()
                }
            }
        }
    }

    private func currentPresentationMode() -> PreviewPresentationMode {
        let previewSize = view.bounds.size
        guard previewSize.width > 0, previewSize.height > 0 else {
            return .compact
        }

        let minimumSize = Self.minimumExpandedPreviewSize
        return previewSize.width >= minimumSize.width && previewSize.height >= minimumSize.height ? .expanded : .compact
    }
}
