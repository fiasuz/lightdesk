import Foundation
import AppKit
import Combine

/// Glue between the UI and the networking/capture/injection services.
final class HostSession: ObservableObject {
    @Published var isRunning = false
    @Published var viewerConnected = false
    @Published var errorMessage: String?
    @Published var localIPs: [String] = []
    @Published var pin: String = ""
    @Published var permissions = PermissionsChecker.currentStatus()

    private let server = WebSocketServer()
    private let capture = ScreenCapture()
    private let mouseInjector = MouseInjector()

    init() {
        server.onViewerConnected = { [weak self] in
            DispatchQueue.main.async { self?.viewerConnected = true }
            self?.capture.start()
        }
        server.onViewerDisconnected = { [weak self] in
            DispatchQueue.main.async { self?.viewerConnected = false }
            self?.capture.stop()
        }
        server.onError = { [weak self] message in
            DispatchQueue.main.async { self?.errorMessage = message }
        }
        server.onMouseMessage = { [weak self] message in
            guard let self else { return }
            let size = NSScreen.main?.frame.size ?? .zero
            self.mouseInjector.handle(message, screenSize: size)
        }
        // Point-space (NSScreen.frame), matching what MouseInjector's CGEvent
        // coordinates use — see MouseCoordinateMath. This is an intentional
        // change from the old nut-js/hardware-pixel convention; the viewer
        // doesn't consume these values for anything, so it's safe.
        server.screenSizeProvider = {
            let size = NSScreen.main?.frame.size ?? .zero
            return (width: Int(size.width), height: Int(size.height))
        }

        capture.onFrame = { [weak self] jpegData in
            self?.server.sendFrame(jpegData)
        }
        capture.onError = { [weak self] message in
            DispatchQueue.main.async { self?.errorMessage = message }
        }
    }

    func refreshPermissions() {
        permissions = PermissionsChecker.currentStatus()
    }

    func start(port: UInt16, password: String) {
        errorMessage = nil
        pin = password

        // Proactively request whatever's missing (rather than only showing a
        // banner) — first Start click triggers the system prompts.
        if !permissions.screenRecording {
            PermissionsChecker.requestScreenRecordingAccess()
        }
        if !permissions.accessibility {
            PermissionsChecker.requestAccessibilityAccess()
        }
        refreshPermissions()

        do {
            try server.start(port: port, password: password)
            isRunning = true
            localIPs = LocalNetworkInfo.ipv4Addresses()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        capture.stop()
        server.stop()
        isRunning = false
        viewerConnected = false
    }
}
