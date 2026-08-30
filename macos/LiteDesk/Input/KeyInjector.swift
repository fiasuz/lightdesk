import CoreGraphics
import ApplicationServices

/// Injects real OS-level keyboard events via CGEvent/CGEventPost, mirroring
/// MouseInjector's serial-queue-plus-accessibility-trust-gate design so key
/// and mouse events from the same viewer apply in the order they were sent.
final class KeyInjector {
    private let queue = DispatchQueue(label: "com.litedesk.keyinjector", qos: .userInteractive)
    private let isTrusted: () -> Bool

    init(isTrusted: @escaping () -> Bool = { AXIsProcessTrusted() }) {
        self.isTrusted = isTrusted
    }

    func handle(_ message: KeyMessage) {
        queue.async { [weak self] in
            self?.process(message)
        }
    }

    private func process(_ message: KeyMessage) {
        guard isTrusted() else { return }

        switch message {
        case .down(let code):
            post(code: code, keyDown: true)
        case .up(let code):
            post(code: code, keyDown: false)
        }
    }

    private func post(code: String, keyDown: Bool) {
        guard let keyCode = KeyCodeMap.keyCode(forDomCode: code) else { return }
        CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: keyDown)?.post(tap: .cghidEventTap)
    }
}
