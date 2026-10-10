import AppKit
import CoreGraphics
import XCTest

final class VideoLayoutTests: XCTestCase {
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
}
