import AppKit
import CoreGraphics
import XCTest

final class PreviewPlayerBindingTests: XCTestCase {
    // The extension and the Renderer Lab both use PreviewPlayerBinding, so these tests
    // cover the wiring of both hosts.
    @MainActor
    func testBindingForwardsEveryPlayerUpdateToTheView() {
        let previewView = PreviewContentView(frame: NSRect(x: 0, y: 0, width: 960, height: 720))
        previewView.setPresentationMode(.expanded)
        let player = PlayerSpy()
        PreviewPlayerBinding.forwardUpdates(from: player, to: previewView)

        player.playbackStateDidChange?(.paused)
        XCTAssertEqual(previewView.placeholderTextForTesting, "Playback paused. Click Play to continue.")

        player.videoOutputVisibilityDidChange?(true)
        XCTAssertFalse(previewView.isPlaceholderVisibleForTesting)

        player.playbackMetricsDidChange?(MediaPreviewPlaybackMetrics(
            position: 0.5, isSeekable: true, elapsedText: "1:23", remainingText: "-1:23"
        ))
        XCTAssertEqual(previewView.elapsedTimeTextForTesting, "1:23")

        player.videoPresentationSizeDidChange?(CGSize(width: 400, height: 400))
        previewView.layoutSubtreeIfNeeded()
        let canvas = previewView.videoCanvasFrameForTesting
        XCTAssertEqual(canvas.width, canvas.height, accuracy: 1, "a square video must get a square canvas")

        player.mediaKindDidChange?(.audioOnly)
        XCTAssertTrue(previewView.isVideoFrameHiddenForTesting)
    }

    @MainActor
    func testBindingRoutesEveryControlToTheCurrentPlayer() throws {
        let previewView = PreviewContentView(frame: NSRect(x: 0, y: 0, width: 960, height: 720))
        previewView.setMediaKind(.video)
        previewView.setPresentationMode(.expanded)
        let first = PlayerSpy()
        // A reference holder: the routing closure is @MainActor (so Sendable) and must
        // not capture a mutable local variable.
        let current = PlayerHolder(first)
        PreviewPlayerBinding.routeControls(of: previewView, to: { current.player }, logContext: "test")

        let playPause = try XCTUnwrap(accessibleButtons(under: previewView).first { $0.accessibilityLabel() == "Play" })
        XCTAssertTrue(playPause.accessibilityPerformPress())
        previewView.seekTrackingHandler?(true, 1)
        previewView.seekHandler?(0.25, false, 1)
        previewView.seekTrackingHandler?(false, 1)
        previewView.volumeHandler?(150, 2)

        XCTAssertEqual(first.togglePlaybackCount, 1)
        XCTAssertEqual(first.scrubbingCalls, ["begin", "end"])
        XCTAssertEqual(first.seekRequests, ["0.25 final=false"])
        XCTAssertEqual(first.requestedVolumes, [150])

        // The extension replaces its player for every new file.
        let second = PlayerSpy()
        current.player = second
        XCTAssertTrue(playPause.accessibilityPerformPress())

        XCTAssertEqual(first.togglePlaybackCount, 1)
        XCTAssertEqual(second.togglePlaybackCount, 1)
    }
}
