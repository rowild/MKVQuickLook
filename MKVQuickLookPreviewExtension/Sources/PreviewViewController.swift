import AppKit
import Quartz

final class PreviewViewController: NSViewController, QLPreviewingController {
    private static let minimumExpandedPreviewSize = NSSize(width: 720, height: 440)
    private static let expandedPreferredContentSize = NSSize(width: 960, height: 600)
    private static let compactPreferredContentSize = NSSize(width: 260, height: 120)

    private let previewContentView = PreviewContentView()
    private var player: MediaPreviewPlayer?
    private var currentFileURL: URL?
    private var lifecycle = PreviewPlaybackLifecycle()

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

    override func viewWillAppear() {
        super.viewWillAppear()
        logLifecycle("will-appear")
        lifecycle.willAppear()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        player?.refreshVideoLayout()
        updatePresentationModeAndPlayback()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        logLifecycle("did-disappear")
        MediaPreviewPlayerSession.previewDidClose(file: currentFileURL, closingPlayer: player)
        applyPlaybackAction(lifecycle.didDisappear())
    }

    func preparePreviewOfFile(at url: URL) async throws {
        do {
            logLifecycle("prepare", file: url)
            MediaPreviewPlayerSession.stopActivePreview()
            let metadata = try PreviewMetadata(fileURL: url)
            let player = VLCKitMediaPreviewPlayer()
            PreviewPlayerBinding.forwardUpdates(from: player, to: previewContentView)

            self.player = MediaPreviewPlayerSession.replace(current: self.player, with: player)

            title = metadata.displayName
            previewContentView.apply(metadata: metadata)
            previewContentView.attachRenderView(player.renderView)

            currentFileURL = url
            lifecycle.prepare()
            updatePresentationModeAndPlayback()
        } catch {
            title = url.lastPathComponent
            previewContentView.apply(error: error.localizedDescription)
            throw error
        }
    }

    private func updatePresentationModeAndPlayback() {
        let mode = currentPresentationMode()
        previewContentView.setPresentationMode(mode)
        preferredContentSize = mode == .expanded ? Self.expandedPreferredContentSize : Self.compactPreferredContentSize
        applyPlaybackAction(lifecycle.layout(mode: mode, hasFile: currentFileURL != nil))
    }

    private func applyPlaybackAction(_ action: PreviewPlaybackLifecycle.Action) {
        switch action {
        case .none:
            break
        case .stop:
            logLifecycle("stop")
            player?.stop()
            MediaPreviewPlayerSession.deactivate(player)
        case .loadAndPlay:
            guard let player, let currentFileURL else { return }
            logLifecycle("autoplay")
            player.loadMedia(from: currentFileURL)
            MediaPreviewPlayerSession.activate(player)
            player.play()
        }
    }

    private func logLifecycle(_ event: String, file: URL? = nil) {
        let controller = String(UInt(bitPattern: ObjectIdentifier(self).hashValue), radix: 16)
        let fileName = (file ?? currentFileURL)?.lastPathComponent ?? "nil"
        PlaybackDiagnostics.log("[ql] \(event) controller=\(controller) file=\(fileName) size=\(NSStringFromSize(view.bounds.size)) t=\(PlaybackDiagnostics.timestampString())")
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
