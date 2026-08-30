import CoreGraphics

// Pure, side-effect-free math extracted out of MouseInjector so it's testable
// without CGEventPost / Accessibility trust. Coordinates are point-space
// (NSScreen.frame), not hardware-pixel space — a deliberate correction versus
// the old nut-js-based Electron app, which operated in hardware pixels.
enum MouseCoordinateMath {
    static func point(forNormalizedX x: Double, y: Double, screenSize: CGSize) -> CGPoint {
        let clampedX = min(max(x, 0), 1)
        let clampedY = min(max(y, 0), 1)
        return CGPoint(x: clampedX * screenSize.width, y: clampedY * screenSize.height)
    }

    // Mirrors mouseControl.js's per-event scroll clamp of 50 "notches" per axis.
    static func clampScrollDelta(_ delta: Double, maxMagnitude: Double = 50) -> Int32 {
        guard !delta.isNaN else { return 0 }
        let magnitude = min(abs(delta), maxMagnitude)
        let signed = delta < 0 ? -magnitude : magnitude
        return Int32(signed.rounded())
    }
}
