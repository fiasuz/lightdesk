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
    @Published var port: UInt16 = 0
    @Published var permissions = PermissionsChecker.currentStatus()
    @Published var tunnelState: CloudflaredTunnelManager.TunnelState = .idle

    private let server = WebSocketServer()
    private let capture = ScreenCapture()
    private let mouseInjector = MouseInjector()
    private let keyInjector = KeyInjector()
    private let tunnelManager = CloudflaredTunnelManager()
    private var cancellables = Set<AnyCancellable>()

    init() {
        tunnelManager.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.tunnelState = state }
            .store(in: &cancellables)

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
            self.mouseInjector.handle(message, screenSize: Self.mainDisplaySize())
        }
        server.onKeyMessage = { [weak self] message in
            self?.keyInjector.handle(message)
        }
        // CGDisplayBounds(CGMainDisplayID()), not NSScreen.main: this callback
        // (and screenSizeProvider below) fire on WebSocketServer's background
        // queue, and NSScreen.main is an AppKit call that's only safe on the
        // main thread — off-thread it can intermittently return nil, which
        // silently fell back to CGSize.zero and collapsed every coordinate to
        // (0,0). CGDisplayBounds is a plain CoreGraphics C call (thread-safe)
        // and also matches ScreenCapture's own CGMainDisplayID() selection,
        // in the same top-left-origin space CGEvent expects.
        server.screenSizeProvider = {
            let size = Self.mainDisplaySize()
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

    func start(port: UInt16, password: String, useTunnel: Bool) {
        errorMessage = nil
        pin = password
        self.port = port

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
            if useTunnel {
                tunnelManager.start(port: port)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        capture.stop()
        server.stop()
        tunnelManager.stop()
        isRunning = false
        viewerConnected = false
    }

    private static func mainDisplaySize() -> CGSize {
        CGDisplayBounds(CGMainDisplayID()).size
    }
}
