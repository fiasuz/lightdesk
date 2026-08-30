import Foundation

// Minimal RFC 6455 frame encode/decode. Deliberately scoped to what this app's
// protocol actually needs: no compression extension, no fragmentation (every
// message here is small/one-shot), text+binary+close+ping/pong opcodes only.
// Kept free of NWConnection so it's testable in isolation.

enum WebSocketOpcode: UInt8 {
    case continuation = 0x0
    case text = 0x1
    case binary = 0x2
    case close = 0x8
    case ping = 0x9
    case pong = 0xA
}

struct WebSocketFrame {
    let opcode: WebSocketOpcode
    let payload: Data
}

enum WebSocketFrameError: Error {
    case protocolError(String)
}

/// Feed raw bytes in as they arrive; get back zero or more complete frames.
/// Buffers incomplete frames across calls.
final class WebSocketFrameDecoder {
    private var buffer = Data()

    func feed(_ data: Data) throws -> [WebSocketFrame] {
        buffer.append(data)
        var frames: [WebSocketFrame] = []
        while true {
            guard let (frame, consumed) = try Self.tryParseFrame(buffer) else { break }
            frames.append(frame)
            buffer.removeFirst(consumed)
        }
        return frames
    }

    private static func tryParseFrame(_ data: Data) throws -> (WebSocketFrame, Int)? {
        let start = data.startIndex
        let count = data.count
        guard count >= 2 else { return nil }

        let byte0 = data[start]
        let byte1 = data[start + 1]

        let fin = (byte0 & 0x80) != 0
        let rsv = byte0 & 0x70
        guard rsv == 0 else { throw WebSocketFrameError.protocolError("RSV bits must be 0 (no extensions supported)") }
        guard fin else { throw WebSocketFrameError.protocolError("fragmented frames are not supported") }
        guard let opcode = WebSocketOpcode(rawValue: byte0 & 0x0F) else {
            throw WebSocketFrameError.protocolError("unknown opcode")
        }

        let masked = (byte1 & 0x80) != 0
        guard masked else { throw WebSocketFrameError.protocolError("client frames must be masked") }

        let lengthIndicator = Int(byte1 & 0x7F)
        var offset = start + 2
        var payloadLength: Int

        if lengthIndicator == 126 {
            guard data.endIndex - offset >= 2 else { return nil }
            payloadLength = (Int(data[offset]) << 8) | Int(data[offset + 1])
            offset += 2
        } else if lengthIndicator == 127 {
            guard data.endIndex - offset >= 8 else { return nil }
            var length: UInt64 = 0
            for i in 0..<8 { length = (length << 8) | UInt64(data[offset + i]) }
            payloadLength = Int(length)
            offset += 8
        } else {
            payloadLength = lengthIndicator
        }

        guard data.endIndex - offset >= 4 else { return nil }
        let maskKey = [data[offset], data[offset + 1], data[offset + 2], data[offset + 3]]
        offset += 4

        guard data.endIndex - offset >= payloadLength else { return nil }
        var unmasked = Data(capacity: payloadLength)
        for i in 0..<payloadLength {
            unmasked.append(data[offset + i] ^ maskKey[i % 4])
        }
        offset += payloadLength

        let consumed = offset - start
        return (WebSocketFrame(opcode: opcode, payload: unmasked), consumed)
    }
}

enum WebSocketFrameEncoder {
    // Server->client frames must NOT be masked (masking is client-to-server only).
    static func encode(opcode: WebSocketOpcode, payload: Data) -> Data {
        var frame = Data()
        frame.append(0x80 | opcode.rawValue) // FIN = 1

        let length = payload.count
        if length <= 125 {
            frame.append(UInt8(length))
        } else if length <= 0xFFFF {
            frame.append(126)
            frame.append(UInt8((length >> 8) & 0xFF))
            frame.append(UInt8(length & 0xFF))
        } else {
            frame.append(127)
            for shift in stride(from: 56, through: 0, by: -8) {
                frame.append(UInt8((UInt64(length) >> shift) & 0xFF))
            }
        }

        frame.append(payload)
        return frame
    }

    static func encodeText(_ data: Data) -> Data {
        encode(opcode: .text, payload: data)
    }

    static func encodeBinary(_ data: Data) -> Data {
        encode(opcode: .binary, payload: data)
    }

    static func encodeClose(code: UInt16, reason: String) -> Data {
        var payload = Data()
        payload.append(UInt8((code >> 8) & 0xFF))
        payload.append(UInt8(code & 0xFF))
        payload.append(reason.data(using: .utf8) ?? Data())
        return encode(opcode: .close, payload: payload)
    }
}
