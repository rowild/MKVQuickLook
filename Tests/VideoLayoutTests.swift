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

    // PreviewContentView insets the video frame bounds by 1 pt. While the frame is
    // still smaller than 2 pt, that yields CGRect.null (infinite origin), which AppKit
    // rejects as "Invalid view geometry".
    func testNullBoundsGiveFiniteRect() {
        let tinyBounds = CGRect(x: 0, y: 0, width: 1, height: 1).insetBy(dx: 1, dy: 1)

        let rect = VideoLayout.fittedRect(contentSize: CGSize(width: 16, height: 9), in: tinyBounds)

        XCTAssertEqual(rect, .zero)
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

    // PreviewViewController.viewDidLayout re-applies the presentation mode on every
    // layout pass (window resize, full screen), including while the video plays.
    @MainActor
    func testPlaceholderStaysHiddenWhenExpandedModeIsReappliedDuringPlayback() {
        let previewView = PreviewContentView(frame: NSRect(x: 0, y: 0, width: 960, height: 720))
        previewView.setPresentationMode(.expanded)
        previewView.updatePlaybackState(.opening)
        previewView.setVideoOutputVisible(true)
        previewView.updatePlaybackState(.playing)

        previewView.setPresentationMode(.expanded)

        XCTAssertFalse(previewView.isPlaceholderVisibleForTesting)
    }

    @MainActor
    func testFailureMessageSurvivesReapplyingExpandedMode() {
        let previewView = PreviewContentView(frame: NSRect(x: 0, y: 0, width: 960, height: 720))
        previewView.setPresentationMode(.expanded)
        previewView.updatePlaybackState(.failed("codec error"))

        previewView.setPresentationMode(.expanded)

        XCTAssertTrue(previewView.isPlaceholderVisibleForTesting)
        XCTAssertEqual(previewView.placeholderTextForTesting, "Playback failed")
    }

    // Video mode hides the Play button; the hover overlay is the only play/pause
    // control, so VoiceOver and other accessibility clients must be able to use it.
    @MainActor
    func testVideoPlayPauseControlIsAnAccessibleButton() throws {
        let previewView = PreviewContentView(frame: NSRect(x: 0, y: 0, width: 960, height: 720))
        previewView.setMediaKind(.video)
        previewView.setPresentationMode(.expanded)
        var toggleCount = 0
        previewView.playbackToggleHandler = { toggleCount += 1 }

        let playButton = try XCTUnwrap(
            accessibleButtons(under: previewView).first { $0.accessibilityLabel() == "Play" },
            "No accessible Play button in expanded video mode"
        )
        XCTAssertTrue(playButton.accessibilityPerformPress())
        XCTAssertEqual(toggleCount, 1)

        previewView.updatePlaybackState(.playing)
        XCTAssertEqual(playButton.accessibilityLabel(), "Pause")
    }

    // Track dictionaries below mirror what VLCKit 3.7.2 reports after parsing the
    // local example-videos samples.
    func testTracksWithOnlyAudioAreAudioOnly() {
        let vorbisOgg: [Any] = [
            ["type": "audio", "codec": 1651666806, "rate": 44100] as [String: Any]
        ]

        XCTAssertEqual(VLCKitMediaPreviewPlayer.mediaKind(fromTracksInformation: vorbisOgg), .audioOnly)
    }

    func testTheoraTrackWithoutParsedSizeStillCountsAsVideo() {
        let theoraOgg: [Any] = [
            ["type": "video", "codec": 1868916852, "width": 0, "height": 0] as [String: Any],
            ["type": "audio", "codec": 1651666806, "rate": 44100] as [String: Any]
        ]

        XCTAssertEqual(VLCKitMediaPreviewPlayer.mediaKind(fromTracksInformation: theoraOgg), .video)
    }

    func testVideoWithAudioAndSubtitlesIsVideo() {
        let mkv: [Any] = [
            ["type": "video", "codec": 875967080, "width": 512, "height": 384] as [String: Any],
            ["type": "audio", "codec": 1630826605, "rate": 44100] as [String: Any],
            ["type": "text", "codec": 1952609651] as [String: Any]
        ]

        XCTAssertEqual(VLCKitMediaPreviewPlayer.mediaKind(fromTracksInformation: mkv), .video)
    }

    func testNoAudioOrVideoTracksGiveNoMediaKind() {
        XCTAssertNil(VLCKitMediaPreviewPlayer.mediaKind(fromTracksInformation: []))
        XCTAssertNil(VLCKitMediaPreviewPlayer.mediaKind(fromTracksInformation: [
            ["type": "text", "codec": 1952609651] as [String: Any]
        ]))
    }

    @MainActor
    func testAudioOnlyExpandedModeShowsPlaybackButton() {
        // The play button is only shown for audio-only mode; video uses the hover overlay instead.
        let previewView = PreviewContentView(frame: NSRect(x: 0, y: 0, width: 960, height: 720))
        previewView.setMediaKind(.audioOnly)
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

    // Finder lays a preview out again after it has closed it (viewDidDisappear), for
    // example in Gallery view. That layout pass must not reload and restart the
    // video out of sight.
    func testClosedPreviewDoesNotStartAgainOnLaterLayout() {
        var lifecycle = PreviewPlaybackLifecycle()
        lifecycle.prepare()
        XCTAssertEqual(lifecycle.layout(mode: .expanded, hasFile: true), .loadAndPlay)

        XCTAssertEqual(lifecycle.didDisappear(), .stop)

        XCTAssertEqual(lifecycle.layout(mode: .expanded, hasFile: true), .none)
    }

    func testClosedPreviewStartsAgainWhenShownAgain() {
        var lifecycle = PreviewPlaybackLifecycle()
        lifecycle.prepare()
        _ = lifecycle.layout(mode: .expanded, hasFile: true)
        _ = lifecycle.didDisappear()

        lifecycle.willAppear()

        XCTAssertEqual(lifecycle.layout(mode: .expanded, hasFile: true), .loadAndPlay)
    }

    func testClosedPreviewStartsAgainWhenPreparedWithAFile() {
        var lifecycle = PreviewPlaybackLifecycle()
        lifecycle.prepare()
        _ = lifecycle.layout(mode: .expanded, hasFile: true)
        _ = lifecycle.didDisappear()

        lifecycle.prepare()

        XCTAssertEqual(lifecycle.layout(mode: .expanded, hasFile: true), .loadAndPlay)
    }

    func testExpandedPreviewLoadsOnlyOnce() {
        var lifecycle = PreviewPlaybackLifecycle()
        lifecycle.prepare()

        XCTAssertEqual(lifecycle.layout(mode: .expanded, hasFile: true), .loadAndPlay)
        XCTAssertEqual(lifecycle.layout(mode: .expanded, hasFile: true), .none)
    }

    func testExpandedPreviewWithoutFileDoesNothing() {
        var lifecycle = PreviewPlaybackLifecycle()

        XCTAssertEqual(lifecycle.layout(mode: .expanded, hasFile: false), .none)
    }

    func testShrinkingToCompactStopsLoadedMediaOnce() {
        var lifecycle = PreviewPlaybackLifecycle()
        lifecycle.prepare()
        _ = lifecycle.layout(mode: .expanded, hasFile: true)

        XCTAssertEqual(lifecycle.layout(mode: .compact, hasFile: true), .stop)
        XCTAssertEqual(lifecycle.layout(mode: .compact, hasFile: true), .none)
        XCTAssertEqual(lifecycle.layout(mode: .expanded, hasFile: true), .loadAndPlay)
    }

    // The compact Finder preview must stay summary-only, even when the player reports
    // the media kind (which re-runs the expanded-mode layout rules).
    @MainActor
    func testCompactModeKeepsVideoFrameAndControlsHiddenWhenMediaKindChanges() {
        let previewView = PreviewContentView(frame: NSRect(x: 0, y: 0, width: 260, height: 120))
        previewView.setPresentationMode(.compact)

        previewView.setMediaKind(.video)

        XCTAssertTrue(previewView.isVideoFrameHiddenForTesting)
        XCTAssertTrue(previewView.isControlsRowHiddenForTesting)
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
            remainingText: "-0:20"
        )

        previewView.updatePlaybackMetrics(metrics)

        XCTAssertEqual(previewView.volumeSliderValueForTesting, 173)
    }

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

@MainActor
private func accessibleButtons(under element: NSAccessibilityProtocol) -> [NSAccessibilityProtocol] {
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
private final class PlayerHolder {
    var player: PlayerSpy?

    init(_ player: PlayerSpy?) {
        self.player = player
    }
}

@MainActor
private final class PlayerSpy: MediaPreviewPlayer {
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

@MainActor
final class RendererSmokeTests: XCTestCase {
    func testReflectionsMKVProducesVisibleVideoFrame() throws {
        try assertVisibleVideoFrame(for: sampleURL(named: "Reflections-test.mkv"))
    }

    func testWebMProducesVisibleVideoFrame() throws {
        try assertVisibleVideoFrame(for: sampleURL(named: "big_buck_bunny_240p.webm"))
    }

    func testLoadMediaReturnsBeforeParsingAndReportsAudioOnlyKindLater() throws {
        let player = VLCKitMediaPreviewPlayer()
        var reportedKinds: [PreviewMediaKind] = []
        let kindReported = expectation(description: "media kind reported")
        player.mediaKindDidChange = {
            reportedKinds.append($0)
            kindReported.fulfill()
        }
        defer { player.stop() }

        player.loadMedia(from: try sampleURL(named: "sample3.ogg"))

        // A synchronous parse inside loadMedia blocks the main thread, and with it the
        // Quick Look window, on large files or slow volumes.
        XCTAssertEqual(reportedKinds, [], "loadMedia must not parse the file synchronously")

        wait(for: [kindReported], timeout: 10)
        XCTAssertEqual(reportedKinds, [.audioOnly])
    }

    // After a stop (another preview took over, or Finder closed this one) the play
    // button must still work: the player reloads its last file instead of doing nothing.
    // A visible video frame is the proof of playback; VLC state names are not (Pitfall #5).
    func testTogglePlaybackAfterStopReloadsAndPlays() throws {
        let player = VLCKitMediaPreviewPlayer()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 360),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = player.renderView
        window.orderFrontRegardless()
        defer {
            player.stop()
            window.orderOut(nil)
        }

        // This sample's audio track is digitally silent, so the test makes no sound.
        player.loadMedia(from: try sampleURL(named: "BeachDrone-AV1.webm"))
        player.stop()

        player.togglePlayback()

        XCTAssertTrue(
            waitUntil(timeout: 10) {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                return player.hasVisibleVideoOutput
            },
            "The play button did nothing after stop()"
        )
    }

    func testLoadMediaReportsParsedVideoPresentationSize() throws {
        let player = VLCKitMediaPreviewPlayer()
        var lastReportedSize: CGSize?
        let sizeReported = expectation(description: "parsed video size reported")
        player.videoPresentationSizeDidChange = { size in
            guard let size else { return }
            lastReportedSize = size
            sizeReported.fulfill()
        }
        defer { player.stop() }

        player.loadMedia(from: try sampleURL(named: "Reflections-test.mkv"))

        wait(for: [sizeReported], timeout: 10)
        XCTAssertEqual(lastReportedSize, CGSize(width: 512, height: 384))
    }

    func testPrimePausedStartCanTransitionToPlaying() throws {
        let url = try sampleURL(named: "Reflections-test.mkv")
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

    private func sampleURL(named name: String) throws -> URL {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("example-videos")
            .appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MissingSampleError(name: name)
        }
        return url
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

private struct MissingSampleError: LocalizedError {
    let name: String

    var errorDescription: String? {
        "Missing local sample example-videos/\(name). See README section \"Developer Test Media\"."
    }
}
