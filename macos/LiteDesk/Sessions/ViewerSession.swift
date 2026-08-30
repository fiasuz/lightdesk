import Foundation
import Combine

final class ViewerSession: ObservableObject {
    @Published var isConnected = false

    private let client = ViewerClient()

    /// Called directly (off the main thread, at capture cadence) with each
    /// incoming JPEG frame — bypasses @Published/SwiftUI re-render on the hot
    /// path. Set by the NSViewRepresentable hosting RemoteSurfaceView.
    var onFrame: ((Data) -> Void)?

    func connect(ip: String, port: Int? = nil, useTLS: Bool = false, password: String, completion: @escaping (Bool, String?) -> Void) {
        client.onAuthResult = { [weak self] (outcome: ViewerAuthOutcome) in
            DispatchQueue.main.async {
                switch outcome {
                case .success:
                    self?.isConnected = true
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
            }
        }
        client.onFrame = { [weak self] data in
            self?.onFrame?(data)
        }
        client.connect(ip: ip, port: port, useTLS: useTLS, password: password)
    }

    func disconnect() {
        client.disconnect()
        isConnected = false
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
}
