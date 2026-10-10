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
        PreviewPlayerBinding.routeControls(
            of: previewContentView,
            to: { [weak self] in self?.player },
            logContext: "lab"
        )
        PreviewPlayerBinding.forwardUpdates(from: player, to: previewContentView)
    }
}
