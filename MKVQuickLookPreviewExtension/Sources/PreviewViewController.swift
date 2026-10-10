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
        PreviewPlayerBinding.routeControls(
            of: previewContentView,
            to: { [weak self] in self?.player },
            logContext: "controller"
        )
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
            PreviewPlayerBinding.forwardUpdates(from: player, to: previewContentView)

            self.player = MediaPreviewPlayerSession.replace(current: self.player, with: player)

            title = metadata.displayName
            previewContentView.apply(metadata: metadata)
            previewContentView.attachRenderView(player.renderView)

            currentFileURL = url
            isMediaLoaded = false
            updatePresentationModeAndPlayback()
        } catch {
            title = url.lastPathComponent
            previewContentView.apply(error: error.localizedDescription)
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
