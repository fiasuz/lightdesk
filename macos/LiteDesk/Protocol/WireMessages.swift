import Foundation

// Exact wire JSON shapes shared with the Windows native app and the legacy
// Electron app (src/main.js / src/renderer/viewer.js). Field names/casing
// must match byte-for-byte for cross-platform interop.

struct TypeEnvelope: Decodable {
    let type: String
}

struct AuthMessage: Codable {
    let type = "auth"
    let password: String

    enum CodingKeys: String, CodingKey { case type, password }
}

struct AuthOkMessage: Codable {
    let type = "auth-ok"
    let width: Int
    let height: Int

    enum CodingKeys: String, CodingKey { case type, width, height }
}

struct AuthFailMessage: Codable {
    let type = "auth-fail"

    enum CodingKeys: String, CodingKey { case type }
}

struct MouseMoveMessage: Codable {
    let type = "mouse-move"
    let x: Double
    let y: Double

    enum CodingKeys: String, CodingKey { case type, x, y }
}

struct MouseDownMessage: Codable {
    let type = "mouse-down"
    let x: Double
    let y: Double
    let button: String

    enum CodingKeys: String, CodingKey { case type, x, y, button }
}

struct MouseUpMessage: Codable {
    let type = "mouse-up"
    let button: String

    enum CodingKeys: String, CodingKey { case type, button }
}

struct MouseScrollMessage: Codable {
    let type = "mouse-scroll"
    let dx: Double
    let dy: Double

    enum CodingKeys: String, CodingKey { case type, dx, dy }
}

enum MouseMessage {
    case move(x: Double, y: Double)
    case down(x: Double, y: Double, button: String)
    case up(button: String)
    case scroll(dx: Double, dy: Double)

    static func parse(_ data: Data) -> MouseMessage? {
        guard let envelope = try? JSONDecoder().decode(TypeEnvelope.self, from: data) else { return nil }
        let decoder = JSONDecoder()
        switch envelope.type {
        case "mouse-move":
            guard let m = try? decoder.decode(MouseMoveMessage.self, from: data) else { return nil }
            return .move(x: m.x, y: m.y)
        case "mouse-down":
            guard let m = try? decoder.decode(MouseDownMessage.self, from: data) else { return nil }
            return .down(x: m.x, y: m.y, button: m.button)
        case "mouse-up":
            guard let m = try? decoder.decode(MouseUpMessage.self, from: data) else { return nil }
            return .up(button: m.button)
        case "mouse-scroll":
            guard let m = try? decoder.decode(MouseScrollMessage.self, from: data) else { return nil }
            return .scroll(dx: m.dx, dy: m.dy)
        default:
            return nil
        }
    }
}

// Keyboard messages. `code` is a layout-independent physical-key identifier
// using the W3C UIEvents KeyboardEvent.code vocabulary (e.g. "KeyA",
// "ShiftLeft", "ArrowLeft") so a macOS viewer can drive a Windows host and
// vice versa without either side knowing the other's native keycode space —
// see KeyCodeMap.swift for the translation table.
struct KeyDownMessage: Codable {
    let type = "key-down"
    let code: String

    enum CodingKeys: String, CodingKey { case type, code }
}

struct KeyUpMessage: Codable {
    let type = "key-up"
    let code: String

    enum CodingKeys: String, CodingKey { case type, code }
}

enum KeyMessage {
    case down(code: String)
    case up(code: String)

    static func parse(_ data: Data) -> KeyMessage? {
        guard let envelope = try? JSONDecoder().decode(TypeEnvelope.self, from: data) else { return nil }
        let decoder = JSONDecoder()
        switch envelope.type {
        case "key-down":
            guard let m = try? decoder.decode(KeyDownMessage.self, from: data) else { return nil }
            return .down(code: m.code)
        case "key-up":
            guard let m = try? decoder.decode(KeyUpMessage.self, from: data) else { return nil }
            return .up(code: m.code)
        default:
            return nil
        }
    }
}
