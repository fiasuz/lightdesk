import Foundation

/// Viewer (client) role — URLSessionWebSocketTask already speaks correct RFC 6455
/// framing (including client-side masking) internally, so no hand-rolled protocol
/// code is needed here, unlike the host-side WebSocketServer.
enum ViewerAuthOutcome {
    case success(width: Int, height: Int)
    case failure(String)
}

final class ViewerClient {
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?

    var onAuthResult: ((ViewerAuthOutcome) -> Void)?
    var onFrame: ((Data) -> Void)?
    var onDisconnected: (() -> Void)?

    /// Connects to a Cloudflare Tunnel hostname over `wss://` — the tunnel
    /// terminates TLS at its edge, so the scheme's default port (443)
    /// applies and no port is embedded in the URL.
    func connect(host: String, password: String) {
        let session = URLSession(configuration: .default)
        self.session = session

        guard let url = Self.buildURL(host: host) else {
            onAuthResult?(.failure("Noto'g'ri manzil"))
            return
        }

        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        sendAuth(password: password)
        receiveLoop()
    }

    func disconnect() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }

    func sendMouseEvent<T: Encodable>(_ message: T) {
        guard let data = try? JSONEncoder().encode(message), let text = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(text)) { _ in }
    }

    /// Pure URL-building logic, split out so it's unit-testable without
    /// spinning up a real URLSession/socket.
    static func buildURL(host: String) -> URL? {
        URL(string: "wss://\(host)/")
    }

    private func sendAuth(password: String) {
        let auth = AuthMessage(password: password)
        guard let data = try? JSONEncoder().encode(auth), let text = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(text)) { [weak self] error in
            if let error {
                self?.onAuthResult?(.failure(error.localizedDescription))
            }
        }
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                self.onDisconnected?()
            case .success(let message):
                switch message {
                case .data(let data):
                    self.onFrame?(data)
                    self.receiveLoop()
                case .string(let text):
                    self.handleText(text)
                    self.receiveLoop()
                @unknown default:
                    self.receiveLoop()
                }
            }
        }
    }

    private func handleText(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        guard let envelope = try? JSONDecoder().decode(TypeEnvelope.self, from: data) else { return }
        switch envelope.type {
        case "auth-ok":
            if let ok = try? JSONDecoder().decode(AuthOkMessage.self, from: data) {
                onAuthResult?(.success(width: ok.width, height: ok.height))
            }
        case "auth-fail":
            onAuthResult?(.failure("Parol noto'g'ri"))
        default:
            break
        }
    }
}
