import AppKit
import CoreGraphics
import XCTest

final class VideoLayoutTests: XCTestCase {
    func testPreviewMetadataTreatsOpusAsAudio() {
        XCTAssertEqual(PreviewMetadata.mediaKind(for: "opus"), .audioOnly)
        XCTAssertEqual(
            PreviewMetadata.typeDescription(for: "opus", contentTypeDescription: nil),
            "Opus Audio"
        )
    }

    func testVolumeFeedbackStateKeepsRequestedVolumeUntilActualCatchesUp() {
        var state = VolumeFeedbackState()
        state.registerRequestedVolume(137)

        XCTAssertEqual(state.effectiveVolume(actualVolume: 100), 137)
        XCTAssertEqual(state.pendingVolume, 137)
        XCTAssertEqual(state.effectiveVolume(actualVolume: 137), 137)
        XCTAssertEqual(state.pendingVolume, 137)
    }

    func testVolumeFeedbackStateFallsBackToActualVolumeWhenNoPendingValueExists() {
        var state = VolumeFeedbackState()

        XCTAssertEqual(state.effectiveVolume(actualVolume: 82), 100)

        state.registerRequestedVolume(91)
        state.clear()

        XCTAssertEqual(state.effectiveVolume(actualVolume: 77), 100)
    }

    func testVolumeFeedbackStateKeepsLatestRequestedVolumeEvenIfPlayerReportsOlderValue() {
        var state = VolumeFeedbackState()

        state.registerRequestedVolume(120)
        XCTAssertEqual(state.effectiveVolume(actualVolume: 120), 120)

        state.registerRequestedVolume(184)

        XCTAssertEqual(state.effectiveVolume(actualVolume: 120), 184)
        XCTAssertEqual(state.pendingVolume, 184)
        XCTAssertEqual(state.effectiveVolume(actualVolume: 140), 184)
        XCTAssertEqual(state.pendingVolume, 184)
    }

    func testCentersFourByThreeVideoInsideWideBounds() {
        let rect = VideoLayout.fittedRect(
            contentSize: CGSize(width: 512, height: 384),
            in: CGRect(x: 0, y: 0, width: 1000, height: 500)
        )

        XCTAssertEqual(rect.origin.x, 167, accuracy: 1)
        XCTAssertEqual(rect.origin.y, 0, accuracy: 1)
        XCTAssertEqual(rect.width, 666, accuracy: 1)
        XCTAssertEqual(rect.height, 500, accuracy: 1)
    }

    func testCentersSixteenByNineVideoInsideTallBounds() {
        let rect = VideoLayout.fittedRect(
            contentSize: CGSize(width: 1920, height: 1080),
            in: CGRect(x: 0, y: 0, width: 600, height: 900)
        )

        XCTAssertEqual(rect.origin.x, 0, accuracy: 1)
        XCTAssertEqual(rect.origin.y, 281, accuracy: 1)
        XCTAssertEqual(rect.width, 600, accuracy: 1)
        XCTAssertEqual(rect.height, 337, accuracy: 1)
    }

    func testReturnsBoundsForInvalidContentSize() {
        let bounds = CGRect(x: 10, y: 20, width: 320, height: 180)
        let rect = VideoLayout.fittedRect(contentSize: .zero, in: bounds)

        XCTAssertEqual(rect, bounds)
    }

    @MainActor
    func testPlaceholderHidesOncePausedFrameIsVisible() {
        let previewView = PreviewContentView(frame: NSRect(x: 0, y: 0, width: 960, height: 720))
        previewView.setPresentationMode(.expanded)
        previewView.updatePlaybackState(.opening)
        previewView.setVideoOutputVisible(false)

        XCTAssertTrue(previewView.isPlaceholderVisibleForTesting)
        XCTAssertEqual(previewView.placeholderTextForTesting, "Preparing video surface...")

        previewView.setVideoOutputVisible(true)
        previewView.updatePlaybackState(.paused)

        XCTAssertFalse(previewView.isPlaceholderVisibleForTesting)
    }

    @MainActor
    func testPlaybackButtonRemainsEnabledWhileOpeningAndBuffering() {
        let previewView = PreviewContentView(frame: NSRect(x: 0, y: 0, width: 960, height: 720))
        previewView.setPresentationMode(.expanded)

        previewView.updatePlaybackState(.opening)
        XCTAssertTrue(previewView.isPlaybackButtonEnabledForTesting)

        previewView.updatePlaybackState(.buffering)
        XCTAssertTrue(previewView.isPlaybackButtonEnabledForTesting)
    }

    @MainActor
    func testAudioOnlyExpandedModeHidesVideoFrameAndKeepsControlsVisible() {
        let previewView = PreviewContentView(frame: NSRect(x: 0, y: 0, width: 960, height: 720))
        previewView.setMediaKind(.audioOnly)
        previewView.setPresentationMode(.expanded)
        previewView.updatePlaybackState(.paused)

        XCTAssertTrue(previewView.isVideoFrameHiddenForTesting)
        XCTAssertFalse(previewView.isControlsRowHiddenForTesting)
    }

    @MainActor
    func testPlaybackMetricsDoNotOverwriteUserControlledVolumeSliderValue() {
        let previewView = PreviewContentView(frame: NSRect(x: 0, y: 0, width: 960, height: 720))
        previewView.setPresentationMode(.expanded)
        previewView.setVolumeSliderValueForTesting(173)

        let metrics = MediaPreviewPlaybackMetrics(
            position: 0.2,
            isSeekable: true,
            elapsedText: "0:10",
            remainingText: "-0:20",
            volume: 40
        )

        previewView.updatePlaybackMetrics(metrics)

        XCTAssertEqual(previewView.volumeSliderValueForTesting, 173)
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

@MainActor
private final class PlayerSpy: MediaPreviewPlayer {
    let renderView = NSView()
    var playbackStateDidChange: ((MediaPreviewPlaybackState) -> Void)?
    var playbackMetricsDidChange: ((MediaPreviewPlaybackMetrics) -> Void)?
    var videoPresentationSizeDidChange: ((CGSize?) -> Void)?
    var videoOutputVisibilityDidChange: ((Bool) -> Void)?
    private(set) var stopCalled = false

    func loadMedia(from url: URL) {}
    func primeForPausedStart() {}
    func play() {}
    func pause() {}
    func setMuted(_ muted: Bool) {}
    func setVolume(_ volume: Int, interactionID: PlaybackDiagnostics.InteractionID?) {}
    func beginScrubbing(interactionID: PlaybackDiagnostics.InteractionID?) {}
    func endScrubbing(interactionID: PlaybackDiagnostics.InteractionID?) {}
    func seek(to position: Float, isFinal: Bool, interactionID: PlaybackDiagnostics.InteractionID?) {}
    func refreshVideoLayout() {}
    func togglePlayback() {}
    func stop() { stopCalled = true }
}

@MainActor
final class RendererSmokeTests: XCTestCase {
    func testReflectionsMKVProducesVisibleVideoFrame() throws {
        try assertVisibleVideoFrame(for: sampleURL(named: "Reflections.mkv"))
    }

    func testWebMProducesVisibleVideoFrame() throws {
        try assertVisibleVideoFrame(for: sampleURL(named: "big_buck_bunny_240p.webm"))
    }

    func testPrimePausedStartCanTransitionToPlaying() throws {
        let url = sampleURL(named: "Reflections.mkv")
        let previewView = PreviewContentView(frame: NSRect(x: 0, y: 0, width: 960, height: 720))
        previewView.setPresentationMode(.expanded)
        previewView.apply(metadata: try PreviewMetadata(fileURL: url))

        let player = VLCKitMediaPreviewPlayer()
        var latestState: MediaPreviewPlaybackState = .idle
        player.playbackStateDidChange = { latestState = $0 }
        previewView.attachRenderView(player.renderView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = previewView
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.displayIfNeeded()
        defer {
            player.stop()
            window.orderOut(nil)
        }

        player.loadMedia(from: url)
        player.primeForPausedStart()

        XCTAssertTrue(
            waitUntil(timeout: 15) {
                previewView.layoutSubtreeIfNeeded()
                player.refreshVideoLayout()
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                if case .paused = latestState {
                    return true
                }
                return false
            },
            "Timed out waiting for paused-ready priming state"
        )

        player.play()

        XCTAssertTrue(
            waitUntil(timeout: 15) {
                previewView.layoutSubtreeIfNeeded()
                player.refreshVideoLayout()
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                return player.hasVisibleVideoOutput
            },
            "Timed out waiting for visible video output after play from paused-ready state"
        )
    }

    private func assertVisibleVideoFrame(for url: URL, file: StaticString = #filePath, line: UInt = #line) throws {
        let previewView = PreviewContentView(frame: NSRect(x: 0, y: 0, width: 960, height: 720))
        previewView.setPresentationMode(.expanded)
        previewView.apply(metadata: try PreviewMetadata(fileURL: url))

        let player = VLCKitMediaPreviewPlayer()
        previewView.attachRenderView(player.renderView)
        previewView.updatePlaybackState(.idle)
        previewView.updateVideoPresentationSize(CGSize(width: 16, height: 9))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = previewView
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.displayIfNeeded()
        defer {
            player.stop()
            window.orderOut(nil)
        }

        player.loadMedia(from: url)
        player.play()

        XCTAssertTrue(
            waitUntil(timeout: 15) {
                previewView.layoutSubtreeIfNeeded()
                player.refreshVideoLayout()
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                return player.hasVisibleVideoOutput
            },
            "Timed out waiting for VLCKit to report visible video output for \(url.lastPathComponent)",
            file: file,
            line: line
        )

        let snapshotURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        player.saveSnapshot(to: snapshotURL, width: 320, height: 0)

        XCTAssertTrue(
            waitUntil(timeout: 10) {
                guard let attributes = try? FileManager.default.attributesOfItem(atPath: snapshotURL.path),
                      let fileSize = attributes[.size] as? NSNumber else {
                    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                    return false
                }

                return fileSize.intValue > 0 && NSImage(contentsOf: snapshotURL) != nil
            },
            "VLCKit did not produce a readable snapshot for \(url.lastPathComponent)",
            file: file,
            line: line
        )
    }

    private func sampleURL(named name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("example-videos")
            .appendingPathComponent(name)
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
        }
        return false
    }
}
