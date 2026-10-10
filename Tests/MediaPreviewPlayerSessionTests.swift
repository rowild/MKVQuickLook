import AppKit
import CoreGraphics
import XCTest

final class MediaPreviewPlayerSessionTests: XCTestCase {
    // When Quick Look moves on to a file it shows with another previewer (for example
    // an AVI), it keeps our hidden preview playing and tells us nothing. Finder does
    // close its column preview of the same file at that moment; that must stop playback.
    @MainActor
    func testClosingAnotherPreviewOfThePlayingFileStopsPlayback() {
        MediaPreviewPlayerSession.stopActivePreview()
        let quickLookPlayer = PlayerSpy()
        quickLookPlayer.loadedFileURL = URL(fileURLWithPath: "/tmp/Pacific-test.mkv")
        MediaPreviewPlayerSession.activate(quickLookPlayer)
        let columnPreviewPlayer = PlayerSpy()

        MediaPreviewPlayerSession.previewDidClose(
            file: URL(fileURLWithPath: "/tmp/Pacific-test.mkv"),
            closingPlayer: columnPreviewPlayer
        )

        XCTAssertTrue(quickLookPlayer.stopCalled)
    }

    @MainActor
    func testClosingAPreviewOfAnotherFileKeepsPlayback() {
        MediaPreviewPlayerSession.stopActivePreview()
        let quickLookPlayer = PlayerSpy()
        quickLookPlayer.loadedFileURL = URL(fileURLWithPath: "/tmp/Pacific-test.mkv")
        MediaPreviewPlayerSession.activate(quickLookPlayer)

        MediaPreviewPlayerSession.previewDidClose(
            file: URL(fileURLWithPath: "/tmp/Reflections-test.mkv"),
            closingPlayer: PlayerSpy()
        )

        XCTAssertFalse(quickLookPlayer.stopCalled)
    }

    @MainActor
    func testClosingThePlayingPreviewItselfIsLeftToItsController() {
        MediaPreviewPlayerSession.stopActivePreview()
        let quickLookPlayer = PlayerSpy()
        quickLookPlayer.loadedFileURL = URL(fileURLWithPath: "/tmp/Pacific-test.mkv")
        MediaPreviewPlayerSession.activate(quickLookPlayer)

        MediaPreviewPlayerSession.previewDidClose(
            file: URL(fileURLWithPath: "/tmp/Pacific-test.mkv"),
            closingPlayer: quickLookPlayer
        )

        XCTAssertFalse(quickLookPlayer.stopCalled)
    }

    @MainActor
    func testReplacingPlayerStopsPreviousPlayer() {
        let current = PlayerSpy()
        let next = PlayerSpy()

        let replaced = MediaPreviewPlayerSession.replace(current: current, with: next)

        XCTAssertTrue(current.stopCalled)
        XCTAssertTrue(replaced === next)
    }

    @MainActor
    func testActivatingNewPlayerStopsPreviousActivePlayer() {
        let first = PlayerSpy()
        let second = PlayerSpy()

        MediaPreviewPlayerSession.activate(first)
        MediaPreviewPlayerSession.activate(second)

        XCTAssertTrue(first.stopCalled)
        XCTAssertFalse(second.stopCalled)
    }

    @MainActor
    func testStoppingActivePreviewStopsCurrentActivePlayer() {
        let active = PlayerSpy()

        MediaPreviewPlayerSession.activate(active)
        MediaPreviewPlayerSession.stopActivePreview()

        XCTAssertTrue(active.stopCalled)
    }
}
