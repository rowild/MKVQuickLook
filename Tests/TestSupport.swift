import AppKit
import XCTest

@MainActor
func accessibleButtons(under element: NSAccessibilityProtocol) -> [NSAccessibilityProtocol] {
    var buttons: [NSAccessibilityProtocol] = []
    for case let child as NSAccessibilityProtocol in element.accessibilityChildren() ?? [] {
        if child.accessibilityRole() == .button {
            buttons.append(child)
        }
        buttons += accessibleButtons(under: child)
    }
    return buttons
}

@MainActor
final class PlayerHolder {
    var player: PlayerSpy?

    init(_ player: PlayerSpy?) {
        self.player = player
    }
}

@MainActor
final class PlayerSpy: MediaPreviewPlayer {
    let renderView = NSView()
    var playbackStateDidChange: ((MediaPreviewPlaybackState) -> Void)?
    var playbackMetricsDidChange: ((MediaPreviewPlaybackMetrics) -> Void)?
    var videoPresentationSizeDidChange: ((CGSize?) -> Void)?
    var videoOutputVisibilityDidChange: ((Bool) -> Void)?
    var mediaKindDidChange: ((PreviewMediaKind) -> Void)?
    var loadedFileURL: URL?
    private(set) var stopCalled = false
    private(set) var togglePlaybackCount = 0
    private(set) var requestedVolumes: [Int] = []
    private(set) var scrubbingCalls: [String] = []
    private(set) var seekRequests: [String] = []

    func loadMedia(from url: URL) {}
    func primeForPausedStart() {}
    func play() {}
    func pause() {}
    func setVolume(_ volume: Int, interactionID: PlaybackDiagnostics.InteractionID?) { requestedVolumes.append(volume) }
    func beginScrubbing(interactionID: PlaybackDiagnostics.InteractionID?) { scrubbingCalls.append("begin") }
    func endScrubbing(interactionID: PlaybackDiagnostics.InteractionID?) { scrubbingCalls.append("end") }
    func seek(to position: Float, isFinal: Bool, interactionID: PlaybackDiagnostics.InteractionID?) {
        seekRequests.append("\(position) final=\(isFinal)")
    }
    func refreshVideoLayout() {}
    func togglePlayback() { togglePlaybackCount += 1 }
    func stop() { stopCalled = true }
}
