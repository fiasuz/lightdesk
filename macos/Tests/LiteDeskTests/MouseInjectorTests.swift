import XCTest
import CoreGraphics
@testable import LiteDesk

// Only tests the Accessibility-trust gate, deliberately WITHOUT ever letting
// isTrusted return true — that would call CGEventPost for real and move this
// machine's actual cursor, which is not something a test suite should do.
final class MouseInjectorTests: XCTestCase {
    func testEveryMessageKindIsGatedByAccessibilityTrustCheck() {
        let gateReached = expectation(description: "permission gate reached for every message kind")
        gateReached.expectedFulfillmentCount = 4

        let injector = MouseInjector(isTrusted: {
            gateReached.fulfill()
            return false // never allow a real CGEventPost from a test run
        })

        let screen = CGSize(width: 1920, height: 1080)
        injector.handle(.move(x: 0.5, y: 0.5), screenSize: screen)
        injector.handle(.down(x: 0.1, y: 0.1, button: "left"), screenSize: screen)
        injector.handle(.up(button: "left"), screenSize: screen)
        injector.handle(.scroll(dx: 5, dy: -5), screenSize: screen)

        wait(for: [gateReached], timeout: 2.0)
    }
}
