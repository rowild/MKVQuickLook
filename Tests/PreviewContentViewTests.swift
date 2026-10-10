import AppKit
import CoreGraphics
import XCTest

final class PreviewContentViewTests: XCTestCase {
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
}
