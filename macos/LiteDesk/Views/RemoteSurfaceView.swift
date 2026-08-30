import AppKit
import ImageIO

protocol RemoteSurfaceViewDelegate: AnyObject {
    func remoteSurfaceViewDidMoveMouse(x: Double, y: Double)
    func remoteSurfaceViewDidPressMouse(x: Double, y: Double, button: String)
    func remoteSurfaceViewDidReleaseMouse(button: String)
    func remoteSurfaceViewDidScroll(dx: Double, dy: Double)
    func remoteSurfaceViewDidPressKey(code: String)
    func remoteSurfaceViewDidReleaseKey(code: String)
}

/// Layer-backed NSView rendering incoming JPEG frames directly onto layer.contents
/// (no SwiftUI view-diffing in the hot ~8fps path) and capturing local mouse input,
/// mirroring viewer.js's canvas + normalizedPos()/mousemove-throttle behavior.
final class RemoteSurfaceView: NSView {
    weak var delegate: RemoteSurfaceViewDelegate?

    private var currentImage: CGImage?
    private var lastMouseMoveSentAt: CFAbsoluteTime = 0
    private let mouseMoveThrottleInterval: CFAbsoluteTime = 0.025 // matches viewer.js's MOUSE_THROTTLE_MS

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.contentsGravity = .resizeAspect
    }

    // Top-left-origin coordinates, matching the JPEG frame's own pixel space and
    // the old viewer.js canvas convention — avoids a manual Y-flip everywhere else.
    override var isFlipped: Bool { true }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        window?.makeFirstResponder(self)
    }

    func present(frameData: Data) {
        guard let source = CGImageSourceCreateWithData(frameData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        currentImage = image
        layer?.contents = image
    }

    // MARK: - Coordinate math

    /// The image is letterboxed within the view via .resizeAspect — normalize
    /// against the actual displayed image rect, not the raw view bounds.
    private func normalizedPoint(for locationInView: NSPoint) -> (x: Double, y: Double)? {
        guard let image = currentImage else { return nil }
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)
        guard imageWidth > 0, imageHeight > 0, bounds.width > 0, bounds.height > 0 else { return nil }

        let viewAspect = bounds.width / bounds.height
        let imageAspect = imageWidth / imageHeight

        let displayedRect: NSRect
        if imageAspect > viewAspect {
            let displayedHeight = bounds.width / imageAspect
            let yOffset = (bounds.height - displayedHeight) / 2
            displayedRect = NSRect(x: 0, y: yOffset, width: bounds.width, height: displayedHeight)
        } else {
            let displayedWidth = bounds.height * imageAspect
            let xOffset = (bounds.width - displayedWidth) / 2
            displayedRect = NSRect(x: xOffset, y: 0, width: displayedWidth, height: bounds.height)
        }
        guard displayedRect.width > 0, displayedRect.height > 0 else { return nil }

        let x = (locationInView.x - displayedRect.minX) / displayedRect.width
        let y = (locationInView.y - displayedRect.minY) / displayedRect.height
        return (Double(min(max(x, 0), 1)), Double(min(max(y, 0), 1)))
    }

    private func location(for event: NSEvent) -> (x: Double, y: Double)? {
        normalizedPoint(for: convert(event.locationInWindow, from: nil))
    }

    // MARK: - Mouse move / drag (throttled)

    override func mouseMoved(with event: NSEvent) { sendMoveThrottled(event) }
    override func mouseDragged(with event: NSEvent) { sendMoveThrottled(event) }
    override func rightMouseDragged(with event: NSEvent) { sendMoveThrottled(event) }
    override func otherMouseDragged(with event: NSEvent) { sendMoveThrottled(event) }

    private func sendMoveThrottled(_ event: NSEvent) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastMouseMoveSentAt >= mouseMoveThrottleInterval else { return }
        guard let point = location(for: event) else { return }
        lastMouseMoveSentAt = now
        delegate?.remoteSurfaceViewDidMoveMouse(x: point.x, y: point.y)
    }

    // MARK: - Mouse down / up

    override func mouseDown(with event: NSEvent) { sendDown(event, button: "left") }
    override func mouseUp(with event: NSEvent) { delegate?.remoteSurfaceViewDidReleaseMouse(button: "left") }

    // Deliberately does NOT call super — suppresses the system context menu,
    // forwarding a plain right mouse-down instead (matches viewer.js's
    // contextmenu preventDefault()).
    override func rightMouseDown(with event: NSEvent) { sendDown(event, button: "right") }
    override func rightMouseUp(with event: NSEvent) { delegate?.remoteSurfaceViewDidReleaseMouse(button: "right") }

    override func otherMouseDown(with event: NSEvent) { sendDown(event, button: "middle") }
    override func otherMouseUp(with event: NSEvent) { delegate?.remoteSurfaceViewDidReleaseMouse(button: "middle") }

    private func sendDown(_ event: NSEvent, button: String) {
        guard let point = location(for: event) else { return }
        delegate?.remoteSurfaceViewDidPressMouse(x: point.x, y: point.y, button: button)
    }

    override func menu(for event: NSEvent) -> NSMenu? { nil }

    // MARK: - Scroll

    override func scrollWheel(with event: NSEvent) {
        delegate?.remoteSurfaceViewDidScroll(dx: Double(event.scrollingDeltaX), dy: Double(event.scrollingDeltaY))
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        guard let code = KeyCodeMap.domCode(forKeyCode: event.keyCode) else { return }
        delegate?.remoteSurfaceViewDidPressKey(code: code)
    }

    override func keyUp(with event: NSEvent) {
        guard let code = KeyCodeMap.domCode(forKeyCode: event.keyCode) else { return }
        delegate?.remoteSurfaceViewDidReleaseKey(code: code)
    }

    // Modifier-only keys (Shift/Control/Option/Command/CapsLock) never generate
    // keyDown/keyUp — only flagsChanged, whose modifierFlags is a bitmask that
    // doesn't by itself say press-vs-release for a given physical key. Track
    // which modifier keyCodes are currently down and toggle off that, not the
    // bitmask, since flagsChanged.keyCode already identifies the specific
    // left/right key that changed.
    private var pressedModifierKeyCodes: Set<UInt16> = []

    override func flagsChanged(with event: NSEvent) {
        guard let code = KeyCodeMap.domCode(forKeyCode: event.keyCode) else { return }
        if pressedModifierKeyCodes.remove(event.keyCode) != nil {
            delegate?.remoteSurfaceViewDidReleaseKey(code: code)
        } else {
            pressedModifierKeyCodes.insert(event.keyCode)
            delegate?.remoteSurfaceViewDidPressKey(code: code)
        }
    }
}
