import XCTest
@testable import LiteDesk

final class MouseCoordinateMathTests: XCTestCase {
    func testPointScalesNormalizedCoordinatesToScreenSize() {
        let screen = CGSize(width: 2000, height: 1000)
        let point = MouseCoordinateMath.point(forNormalizedX: 0.5, y: 0.25, screenSize: screen)
        XCTAssertEqual(point.x, 1000, accuracy: 0.001)
        XCTAssertEqual(point.y, 250, accuracy: 0.001)
    }

    func testPointClampsOutOfRangeNormalizedCoordinates() {
        let screen = CGSize(width: 1000, height: 1000)
        let overshoot = MouseCoordinateMath.point(forNormalizedX: 1.5, y: -0.5, screenSize: screen)
        XCTAssertEqual(overshoot.x, 1000, accuracy: 0.001)
        XCTAssertEqual(overshoot.y, 0, accuracy: 0.001)
    }

    func testPointAtOriginAndFarCorner() {
        let screen = CGSize(width: 1920, height: 1080)
        XCTAssertEqual(MouseCoordinateMath.point(forNormalizedX: 0, y: 0, screenSize: screen), .zero)
        let farCorner = MouseCoordinateMath.point(forNormalizedX: 1, y: 1, screenSize: screen)
        XCTAssertEqual(farCorner.x, 1920, accuracy: 0.001)
        XCTAssertEqual(farCorner.y, 1080, accuracy: 0.001)
    }

    func testScrollClampPreservesSignAndCapsMagnitude() {
        XCTAssertEqual(MouseCoordinateMath.clampScrollDelta(10), 10)
        XCTAssertEqual(MouseCoordinateMath.clampScrollDelta(-10), -10)
        XCTAssertEqual(MouseCoordinateMath.clampScrollDelta(500), 50)
        XCTAssertEqual(MouseCoordinateMath.clampScrollDelta(-500), -50)
        XCTAssertEqual(MouseCoordinateMath.clampScrollDelta(0), 0)
    }

    func testScrollClampRejectsNonFiniteInput() {
        XCTAssertEqual(MouseCoordinateMath.clampScrollDelta(.nan), 0)
        XCTAssertEqual(MouseCoordinateMath.clampScrollDelta(.infinity), 50)
    }
}
