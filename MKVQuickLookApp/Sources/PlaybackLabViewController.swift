import AppKit

@MainActor
final class PlaybackLabViewController: NSViewController {
    private let previewContentView = PreviewContentView()
    private let player = VLCKitMediaPreviewPlayer()
    private var currentFileURL: URL?

    override func loadView() {
        view = previewContentView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configurePreview()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        player.refreshVideoLayout()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        player.stop()
        MediaPreviewPlayerSession.deactivate(player)
    }

    func loadFile(_ url: URL?) {
        guard currentFileURL != url else {
            return
        }

        currentFileURL = url
        player.stop()

        guard let url else {
            title = "Renderer Lab"
            previewContentView.applyPlaceholder(
                title: "Renderer Lab",
                subtitle: "No media file loaded",
                details: "Use Open Media to load a sample file and validate centering, controls, and layout using the same shared VLCKit renderer as the Quick Look extension.",
                status: "Waiting for a file."
            )
            return
        }

        do {
            let metadata = try PreviewMetadata(fileURL: url)
            title = metadata.displayName
            previewContentView.apply(metadata: metadata)
            previewContentView.attachRenderView(player.renderView)
            player.loadMedia(from: url)
            player.primeForPausedStart()
        } catch {
            title = "Renderer Lab"
            previewContentView.apply(error: error.localizedDescription)
        }
    }

    private func configurePreview() {
        previewContentView.setPresentationMode(.expanded)
        previewContentView.applyPlaceholder(
            title: "Renderer Lab",
            subtitle: "No media file loaded",
            details: "Use Open Media to load a sample file and validate centering, controls, and layout using the same shared VLCKit renderer as the Quick Look extension.",
            status: "Waiting for a file."
        )
        previewContentView.attachRenderView(player.renderView)
        previewContentView.playbackToggleHandler = { [weak self] in
            guard let self else {
                return
            }

            MediaPreviewPlayerSession.activate(self.player)
            self.player.togglePlayback()
        }
        previewContentView.seekTrackingHandler = { [weak self] isTracking, interactionID in
            guard let self else {
                return
            }

            if isTracking {
                PlaybackDiagnostics.log("[seek] lab-begin id=\(interactionID) t=\(PlaybackDiagnostics.timestampString())")
                self.player.beginScrubbing(interactionID: interactionID)
            } else {
                PlaybackDiagnostics.log("[seek] lab-end id=\(interactionID) t=\(PlaybackDiagnostics.timestampString())")
                self.player.endScrubbing(interactionID: interactionID)
            }
        }
        previewContentView.seekHandler = { [weak self] position, isFinal, interactionID in
            PlaybackDiagnostics.log("[seek] lab-change id=\(interactionID ?? 0) position=\(String(format: "%.4f", position)) final=\(isFinal) t=\(PlaybackDiagnostics.timestampString())")
            self?.player.seek(to: position, isFinal: isFinal, interactionID: interactionID)
        }
        previewContentView.volumeHandler = { [weak self] volume, interactionID in
            PlaybackDiagnostics.log("[volume] lab-change id=\(interactionID) target=\(volume) t=\(PlaybackDiagnostics.timestampString())")
            self?.player.setVolume(volume, interactionID: interactionID)
        }

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
    }
}
