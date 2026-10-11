import AppKit
import CoreGraphics
import VLCKit
import XCTest

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

    // VLCKit bug: when a player is released while a play waits behind an asynchronous
    // stop, VLCKit starts that playback during the release and then frees the player;
    // the new playback sends its events into freed memory, and the process crashes in
    // `libvlc_event_send` (Pitfall #25). Without the fix this crashed within 20 rounds.
    func testReleasingAPlayerRightAfterStopAndPlayDoesNotCrash() throws {
        // This sample's audio track is digitally silent, so the test makes no sound.
        let url = try sampleURL(named: "BeachDrone-AV1.webm")
        for _ in 0..<40 {
            autoreleasepool {
                let player = VLCKitMediaPreviewPlayer()
                player.loadMedia(from: url)
                player.play()
                RunLoop.current.run(until: Date().addingTimeInterval(0.12))
                player.stop()
                // The previous file is still closing, so this play has to wait.
                player.loadMedia(from: url)
                player.play()
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        }
    }

    // The player must match the volume slider: every new preview starts at 35%.
    func testNewPlayerStartsAt35PercentVolume() {
        XCTAssertEqual(VLCKitMediaPreviewPlayer().volumeForTesting, 35)
    }

    // VLC must never save its settings: that save can freeze the process (Pitfall #20).
    // VLC refuses the save when its settings file is read-only, and logs the refusal.
    func testVLCRefusesToSaveItsSettings() throws {
        continueAfterFailure = false
        let player = VLCKitMediaPreviewPlayer()
        let settingsFile = VLCEngineConfiguration.settingsFileURL
        // Stops the test before playback, so VLC cannot write VLC.app's settings file.
        let settingsBefore = try FileManager.default.attributesOfItem(atPath: settingsFile.path)
        XCTAssertEqual((settingsBefore[.posixPermissions] as? NSNumber)?.intValue, 0o444)
        let vlcAppSettings = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/org.videolan.vlc/vlcrc")
        let vlcAppSettingsDateBefore = modificationDate(of: vlcAppSettings)

        let errorLog = VLCErrorLog()
        VLCLibrary.shared().loggers = [errorLog]
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 360),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = player.renderView
        window.orderFrontRegardless()
        defer {
            VLCLibrary.shared().loggers = nil
            window.orderOut(nil)
        }

        // This sample's audio track is digitally silent, so the test makes no sound.
        player.loadMedia(from: try sampleURL(named: "BeachDrone-AV1.webm"))
        player.play()
        XCTAssertTrue(
            waitUntil(timeout: 10) {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                return player.hasVisibleVideoOutput
            },
            "No playback"
        )
        // Both change VLC's settings in memory: the volume, and the audio device that
        // the audio output records when it closes at stop.
        player.setVolume(20, interactionID: nil)
        player.stop()

        XCTAssertTrue(
            waitUntil(timeout: 10) {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                return errorLog.contains("configuration file is read-only")
            },
            "VLC did not refuse to save its settings"
        )
        let settingsAfter = try FileManager.default.attributesOfItem(atPath: settingsFile.path)
        XCTAssertEqual(settingsAfter[.modificationDate] as? Date, settingsBefore[.modificationDate] as? Date)
        XCTAssertEqual(settingsAfter[.size] as? NSNumber, settingsBefore[.size] as? NSNumber)
        XCTAssertEqual(modificationDate(of: vlcAppSettings), vlcAppSettingsDateBefore, "VLC changed VLC.app's settings file")
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

    private func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
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

// Collects VLC's error messages. VLC calls it on its own threads.
private final class VLCErrorLog: NSObject, VLCLogging, @unchecked Sendable {
    var level: VLCLogLevel = .error
    private let lock = NSLock()
    private var messages: [String] = []

    func handleMessage(_ message: String, logLevel level: VLCLogLevel, context: VLCLogContext?) {
        lock.withLock { messages.append(message) }
    }

    func contains(_ text: String) -> Bool {
        lock.withLock { messages.contains { $0.contains(text) } }
    }
}

private struct MissingSampleError: LocalizedError {
    let name: String

    var errorDescription: String? {
        "Missing local sample example-videos/\(name). See README section \"Developer Test Media\"."
    }
}
