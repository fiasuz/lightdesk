import Foundation
import AppKit
import Combine

/// Glue between the UI and the networking/capture/injection services.
final class HostSession: ObservableObject {
    @Published var isRunning = false
    @Published var viewerConnected = false
    @Published var errorMessage: String?
    @Published var pin: String = ""
    @Published var permissions = PermissionsChecker.currentStatus()
    @Published var tunnelState: CloudflaredTunnelManager.TunnelState = .idle
    @Published var pingMs: Double?
    @Published var outgoingFps: Double = 0
    @Published var outgoingKbps: Double = 0

    /// Every Cloudflare quick tunnel lives under this domain — the code shown
    /// to the user strips it off (see `connectionCode(pin:tunnelURL:)`), and
    /// the viewer's connect panel re-adds it when parsing what was pasted.
    static let tunnelDomainSuffix = ".trycloudflare.com"

    private let server = WebSocketServer()
    private let capture = ScreenCapture()
    private let mouseInjector = MouseInjector()
    private let keyInjector = KeyInjector()
    private let tunnelManager = CloudflaredTunnelManager()
    private var cancellables = Set<AnyCancellable>()

    private var statsTimer: Timer?
    private var pingTimer: Timer?
    private var frameCountThisSecond = 0
    private var byteCountThisSecond = 0

    init() {
        tunnelManager.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.tunnelState = state }
            .store(in: &cancellables)

        server.onViewerConnected = { [weak self] in
            DispatchQueue.main.async {
                self?.viewerConnected = true
                self?.startLiveStatsTracking()
            }
            self?.capture.start()
        }
        server.onViewerDisconnected = { [weak self] in
            DispatchQueue.main.async {
                self?.viewerConnected = false
                self?.stopLiveStatsTracking()
            }
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
        server.onPongMessage = { [weak self] ts in
            DispatchQueue.main.async {
                self?.pingMs = max(0, (Date().timeIntervalSince1970 - ts) * 1000)
            }
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
            self?.recordOutgoingFrame(bytes: jpegData.count)
        }
        capture.onError = { [weak self] message in
            DispatchQueue.main.async { self?.errorMessage = message }
        }
    }

    func refreshPermissions() {
        permissions = PermissionsChecker.currentStatus()
    }

    /// Fixed local bind port for the WebSocket server / tunnel forward target
    /// — no longer user-configurable now that LAN connections are gone and
    /// the viewer only ever reaches this over the Cloudflare Tunnel.
    private static let port: UInt16 = 5900

    /// Starts hosting with a fresh PIN if not already running — called when
    /// the home screen appears, so an address is always ready to share
    /// without requiring an explicit "start hosting" step.
    func startIfNeeded() {
        guard !isRunning else { return }
        start(password: Self.generatePin())
    }

    /// Stops and restarts with a new PIN — the "Yangi manzil" action.
    func regenerate() {
        stop()
        start(password: Self.generatePin())
    }

    func start(password: String) {
        let port = Self.port
        errorMessage = nil
        pin = password

        // Proactively request whatever's missing (rather than only showing a
        // banner) — hosting starts automatically, so this is effectively the
        // app's first-launch permission prompt.
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
            tunnelManager.start(port: port)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        capture.stop()
        server.stop()
        tunnelManager.stop()
        stopLiveStatsTracking()
        isRunning = false
        viewerConnected = false
    }

    /// The single code shared with the other side: "<PIN>-<tunnel subdomain,
    /// without the shared .trycloudflare.com suffix>". `nil` until the
    /// tunnel is actually up.
    var connectionCode: String? {
        guard case let .running(url) = tunnelState else { return nil }
        return Self.connectionCode(pin: pin, tunnelURL: url)
    }

    static func connectionCode(pin: String, tunnelURL: String) -> String {
        var host = tunnelURL
        for prefix in ["https://", "http://"] where host.hasPrefix(prefix) {
            host.removeFirst(prefix.count)
        }
        host = host.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if host.hasSuffix(tunnelDomainSuffix) {
            host.removeLast(tunnelDomainSuffix.count)
        }
        return "\(pin)-\(host)"
    }

    private static func generatePin() -> String {
        String(format: "%06d", Int.random(in: 100_000...999_999))
    }

    // MARK: - Live stats (ping / FPS / throughput while a viewer is connected)

    private func startLiveStatsTracking() {
        pingMs = nil
        frameCountThisSecond = 0
        byteCountThisSecond = 0
        statsTimer?.invalidate()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.outgoingFps = Double(self.frameCountThisSecond)
            self.outgoingKbps = Double(self.byteCountThisSecond) * 8 / 1000
            self.frameCountThisSecond = 0
            self.byteCountThisSecond = 0
        }
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.server.sendPing()
        }
    }

    private func stopLiveStatsTracking() {
        statsTimer?.invalidate()
        statsTimer = nil
        pingTimer?.invalidate()
        pingTimer = nil
        pingMs = nil
        outgoingFps = 0
        outgoingKbps = 0
    }

    /// Counts real captured/sent frames — `ScreenCapture` genuinely produces
    /// frames at ~8fps, so this reports the actual outgoing rate, not a
    /// fixed/fake number.
    private func recordOutgoingFrame(bytes: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.frameCountThisSecond += 1
            self.byteCountThisSecond += bytes
        }
    }

    private static func mainDisplaySize() -> CGSize {
        CGDisplayBounds(CGMainDisplayID()).size
    }
}
