import AppKit
import CoreGraphics
import XCTest

final class PreviewPlaybackLifecycleTests: XCTestCase {
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
}
