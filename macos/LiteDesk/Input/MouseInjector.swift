import CoreGraphics
import ApplicationServices

/// Injects real OS-level mouse events via CGEvent/CGEventPost, serialized through
/// a dedicated serial queue so events apply in strict arrival order (replacing the
/// old Electron app's Promise-chain mouseQueue).
///
/// IMPORTANT: CGEventPost to .cghidEventTap silently no-ops (no error, nothing
/// happens) when the process is not Accessibility-trusted — so this gates on
/// AXIsProcessTrusted() proactively rather than letting injection fail silently.
final class MouseInjector {
    private let queue = DispatchQueue(label: "com.litedesk.mouseinjector", qos: .userInteractive)
    private let isTrusted: () -> Bool

    private var currentPosition = CGPoint.zero
    private var currentlyPressedButton: CGMouseButton?

    init(isTrusted: @escaping () -> Bool = { AXIsProcessTrusted() }) {
        self.isTrusted = isTrusted
    }

    func handle(_ message: MouseMessage, screenSize: CGSize) {
        queue.async { [weak self] in
            self?.process(message, screenSize: screenSize)
        }
    }

    private func process(_ message: MouseMessage, screenSize: CGSize) {
        // TEMP DIAGNOSTIC — remove once the live-move bug is root-caused.
        WebSocketServer.debugLog("INJECT \(message) trusted=\(isTrusted()) screenSize=\(screenSize)")
        guard isTrusted() else { return }

        switch message {
        case .move(let x, let y):
            currentPosition = MouseCoordinateMath.point(forNormalizedX: x, y: y, screenSize: screenSize)
            post(moveOrDragEvent())

        case .down(let x, let y, let buttonName):
            currentPosition = MouseCoordinateMath.point(forNormalizedX: x, y: y, screenSize: screenSize)
            // Post an explicit .mouseMoved to currentPosition before the
            // click: on macOS, leftMouseDown/Up's mouseCursorPosition field
            // does not reliably warp the *visible* cursor by itself — only
            // .mouseMoved/*Dragged events do. Without this, a down that
            // isn't preceded by a move to the same spot makes the cursor
            // jump on click. Mirrors windows/.../MouseInjector.cs's explicit
            // MoveTo() before ButtonEvent().
            post(CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: currentPosition, mouseButton: .left))
            let button = cgButton(for: buttonName)
            currentlyPressedButton = button
            post(buttonEvent(down: true, button: button))

        case .up(let buttonName):
            let button = cgButton(for: buttonName)
            post(buttonEvent(down: false, button: button))
            if currentlyPressedButton == button {
                currentlyPressedButton = nil
            }

        case .scroll(let dx, let dy):
            post(scrollEvent(dx: dx, dy: dy))
        }
    }

    // A move while a button is held down must be a *Dragged event, not .mouseMoved,
    // or the OS won't treat it as a drag (e.g. text selection, window dragging).
    // This is a correctness fix versus the old app's plain mouse.setPosition, which
    // left drag semantics entirely implicit in whatever the OS's last button state was.
    private func moveOrDragEvent() -> CGEvent? {
        guard let pressed = currentlyPressedButton else {
            return CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: currentPosition, mouseButton: .left)
        }
        let type: CGEventType
        switch pressed {
        case .left: type = .leftMouseDragged
        case .right: type = .rightMouseDragged
        default: type = .otherMouseDragged
        }
        return CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: currentPosition, mouseButton: pressed)
    }

    private func buttonEvent(down: Bool, button: CGMouseButton) -> CGEvent? {
        let type: CGEventType
        switch (button, down) {
        case (.left, true): type = .leftMouseDown
        case (.left, false): type = .leftMouseUp
        case (.right, true): type = .rightMouseDown
        case (.right, false): type = .rightMouseUp
        case (_, true): type = .otherMouseDown
        case (_, false): type = .otherMouseUp
        }
        return CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: currentPosition, mouseButton: button)
    }

    // NOTE (unverified without a real device — see plan/coordinator note): browser
    // `wheel` events report deltaY>0 for "scroll down" (the old mouseControl.js
    // calls mouse.scrollDown for deltaY>0). CGEventCreateScrollWheelEvent's wheel1
    // is documented/observed the other way round (positive = content moves up), so
    // this negates dy/dx as a best-effort match. MUST be confirmed on a real Mac
    // and flipped here if scrolling feels inverted.
    private func scrollEvent(dx: Double, dy: Double) -> CGEvent? {
        let wheel1 = -MouseCoordinateMath.clampScrollDelta(dy)
        let wheel2 = -MouseCoordinateMath.clampScrollDelta(dx)
        return CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: wheel1, wheel2: wheel2, wheel3: 0)
    }

    private func cgButton(for name: String) -> CGMouseButton {
        switch name {
        case "right": return .right
        case "middle": return .center
        default: return .left
        }
    }

    private func post(_ event: CGEvent?) {
        event?.post(tap: .cghidEventTap)
    }
}
