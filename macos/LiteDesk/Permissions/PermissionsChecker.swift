import Foundation
import CoreGraphics
import ApplicationServices

enum PermissionsChecker {
    struct Status {
        let screenRecording: Bool
        let accessibility: Bool
        var allGranted: Bool { screenRecording && accessibility }
    }

    static func currentStatus() -> Status {
        Status(screenRecording: hasScreenRecordingAccess(), accessibility: hasAccessibilityAccess())
    }

    static func hasScreenRecordingAccess() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    static func requestScreenRecordingAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func hasAccessibilityAccess() -> Bool {
        AXIsProcessTrusted()
    }

    // Shows the system's "add to Accessibility list" prompt.
    @discardableResult
    static func requestAccessibilityAccess() -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options)
    }
}
