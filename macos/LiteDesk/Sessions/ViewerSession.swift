import Foundation
import Combine

final class ViewerSession: ObservableObject {
    @Published var isConnected = false
    @Published var connectedHost: String = ""
    @Published var connectedAt: Date?
    @Published var pingMs: Double?
    @Published var incomingFps: Double = 0
    @Published var incomingKbps: Double = 0
    /// Last ~60 one-second samples, for the active-session sparklines.
    @Published var pingHistory: [Double] = []
    @Published var fpsHistory: [Double] = []

    private let client = ViewerClient()
    private var statsTimer: Timer?
    private var pingTimer: Timer?
    private var frameCountThisSecond = 0
    private var byteCountThisSecond = 0

    /// Called directly (off the main thread, at capture cadence) with each
    /// incoming JPEG frame — bypasses @Published/SwiftUI re-render on the hot
    /// path. Set by the NSViewRepresentable hosting RemoteSurfaceView.
    var onFrame: ((Data) -> Void)?

    func connect(host: String, password: String, completion: @escaping (Bool, String?) -> Void) {
        client.onAuthResult = { [weak self] (outcome: ViewerAuthOutcome) in
            DispatchQueue.main.async {
                switch outcome {
                case .success:
                    self?.isConnected = true
                    self?.connectedHost = host
                    self?.connectedAt = Date()
                    self?.startLiveStatsTracking()
                    completion(true, nil)
                case .failure(let message):
                    self?.isConnected = false
                    completion(false, message)
                }
            }
        }
        client.onDisconnected = { [weak self] in
            DispatchQueue.main.async {
                self?.isConnected = false
                self?.stopLiveStatsTracking()
            }
        }
        client.onFrame = { [weak self] data in
            self?.recordIncomingFrame(bytes: data.count)
            self?.onFrame?(data)
        }
        client.onPongTimestamp = { [weak self] ts in
            DispatchQueue.main.async {
                self?.pingMs = max(0, (Date().timeIntervalSince1970 - ts) * 1000)
            }
        }
        client.connect(host: host, password: password)
    }

    func disconnect() {
        client.disconnect()
        isConnected = false
        connectedAt = nil
        stopLiveStatsTracking()
    }

    func sendMouseEvent<T: Encodable>(_ message: T) {
        client.sendMouseEvent(message)
    }

    func sendMouseMove(x: Double, y: Double) {
        sendMouseEvent(MouseMoveMessage(x: x, y: y))
    }

    func sendMouseDown(x: Double, y: Double, button: String) {
        sendMouseEvent(MouseDownMessage(x: x, y: y, button: button))
    }

    func sendMouseUp(button: String) {
        sendMouseEvent(MouseUpMessage(button: button))
    }

    func sendMouseScroll(dx: Double, dy: Double) {
        sendMouseEvent(MouseScrollMessage(dx: dx, dy: dy))
    }

    func sendKeyDown(code: String) {
        sendMouseEvent(KeyDownMessage(code: code))
    }

    func sendKeyUp(code: String) {
        sendMouseEvent(KeyUpMessage(code: code))
    }

    // MARK: - Live stats (ping / FPS / throughput while connected)

    private func startLiveStatsTracking() {
        pingMs = nil
        pingHistory = []
        fpsHistory = []
        frameCountThisSecond = 0
        byteCountThisSecond = 0
        statsTimer?.invalidate()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.incomingFps = Double(self.frameCountThisSecond)
            self.incomingKbps = Double(self.byteCountThisSecond) * 8 / 1000
            self.frameCountThisSecond = 0
            self.byteCountThisSecond = 0
            self.fpsHistory.append(self.incomingFps)
            if self.fpsHistory.count > 60 { self.fpsHistory.removeFirst() }
            self.pingHistory.append(self.pingMs ?? 0)
            if self.pingHistory.count > 60 { self.pingHistory.removeFirst() }
        }
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.client.sendPing()
        }
    }

    private func stopLiveStatsTracking() {
        statsTimer?.invalidate()
        statsTimer = nil
        pingTimer?.invalidate()
        pingTimer = nil
        pingMs = nil
        incomingFps = 0
        incomingKbps = 0
    }

    /// Counts real received frames/bytes — reports the actual incoming rate,
    /// not a fixed/fake number.
    private func recordIncomingFrame(bytes: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.frameCountThisSecond += 1
            self.byteCountThisSecond += bytes
        }
    }
}
