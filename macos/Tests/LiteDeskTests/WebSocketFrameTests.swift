import XCTest
@testable import LiteDesk

final class WebSocketFrameTests: XCTestCase {
    func testServerEncodesUnmaskedTextFrame() {
        let payload = Data("hello".utf8)
        let frame = WebSocketFrameEncoder.encode(opcode: .text, payload: payload)
        // FIN=1, opcode=text(0x1) -> 0x81; length 5, no mask bit.
        XCTAssertEqual(frame[frame.startIndex], 0x81)
        XCTAssertEqual(frame[frame.startIndex + 1], 5)
        XCTAssertEqual(frame.suffix(5), payload)
    }

    func testServerEncodesExtendedLength126Payload() {
        let payload = Data(repeating: 0x41, count: 200)
        let frame = WebSocketFrameEncoder.encode(opcode: .binary, payload: payload)
        XCTAssertEqual(frame[frame.startIndex], 0x82)
        XCTAssertEqual(frame[frame.startIndex + 1], 126)
        let lenBytes = frame[(frame.startIndex + 2)...(frame.startIndex + 3)]
        let len = (Int(lenBytes.first!) << 8) | Int(lenBytes.last!)
        XCTAssertEqual(len, 200)
    }

    func testCloseFrameCarriesCodeAndReason() {
        let frame = WebSocketFrameEncoder.encodeClose(code: 1000, reason: "busy")
        XCTAssertEqual(frame[frame.startIndex], 0x88)
        let payload = frame.suffix(from: frame.startIndex + 2)
        let code = (UInt16(payload.first!) << 8) | UInt16(payload.dropFirst().first!)
        XCTAssertEqual(code, 1000)
        XCTAssertEqual(String(data: payload.dropFirst(2), encoding: .utf8), "busy")
    }

    func testDecoderRoundTripsAMaskedClientFrame() throws {
        let originalPayload = Data(#"{"type":"auth","password":"123456"}"#.utf8)
        let maskKey: [UInt8] = [0x12, 0x34, 0x56, 0x78]
        var masked = Data()
        for (i, byte) in originalPayload.enumerated() {
            masked.append(byte ^ maskKey[i % 4])
        }

        var raw = Data()
        raw.append(0x81) // FIN + text opcode
        raw.append(0x80 | UInt8(originalPayload.count)) // masked, length < 126
        raw.append(contentsOf: maskKey)
        raw.append(masked)

        let decoder = WebSocketFrameDecoder()
        let frames = try decoder.feed(raw)
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].opcode, .text)
        XCTAssertEqual(frames[0].payload, originalPayload)
    }

    func testDecoderBuffersAcrossPartialReads() throws {
        let originalPayload = Data(#"{"type":"mouse-move","x":0.5,"y":0.25}"#.utf8)
        let maskKey: [UInt8] = [0x01, 0x02, 0x03, 0x04]
        var masked = Data()
        for (i, byte) in originalPayload.enumerated() {
            masked.append(byte ^ maskKey[i % 4])
        }
        var raw = Data()
        raw.append(0x81)
        raw.append(0x80 | UInt8(originalPayload.count))
        raw.append(contentsOf: maskKey)
        raw.append(masked)

        let decoder = WebSocketFrameDecoder()
        let splitPoint = raw.count / 2
        let firstHalf = raw.prefix(splitPoint)
        let secondHalf = raw.suffix(from: raw.startIndex + splitPoint)

        let firstResult = try decoder.feed(Data(firstHalf))
        XCTAssertEqual(firstResult.count, 0, "should not yield a frame until fully buffered")

        let secondResult = try decoder.feed(Data(secondHalf))
        XCTAssertEqual(secondResult.count, 1)
        XCTAssertEqual(secondResult[0].payload, originalPayload)
    }

    func testRejectsUnmaskedClientFrame() {
        var raw = Data()
        raw.append(0x81)
        raw.append(0x05) // mask bit NOT set — invalid for a client frame
        raw.append(Data("hello".utf8))

        let decoder = WebSocketFrameDecoder()
        XCTAssertThrowsError(try decoder.feed(raw))
    }
}
