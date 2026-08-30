import XCTest
@testable import LiteDesk

final class KeyCodeMapTests: XCTestCase {
    func testCommonKeysRoundTripThroughDomCode() {
        let samples: [UInt16] = [0x00, 0x31, 0x24, 0x35, 0x7B, 0x7E, 0x38, 0x3B]
        for keyCode in samples {
            guard let code = KeyCodeMap.domCode(forKeyCode: keyCode) else {
                XCTFail("expected a DOM code for keyCode \(keyCode)")
                continue
            }
            XCTAssertEqual(KeyCodeMap.keyCode(forDomCode: code), keyCode)
        }
    }

    func testUnknownKeyCodeReturnsNil() {
        XCTAssertNil(KeyCodeMap.domCode(forKeyCode: 0xFF))
    }

    func testUnknownDomCodeReturnsNil() {
        XCTAssertNil(KeyCodeMap.keyCode(forDomCode: "NotARealCode"))
    }

    func testLeftAndRightModifiersMapToDistinctCodes() {
        XCTAssertEqual(KeyCodeMap.domCode(forKeyCode: 0x38), "ShiftLeft")
        XCTAssertEqual(KeyCodeMap.domCode(forKeyCode: 0x3C), "ShiftRight")
    }
}
