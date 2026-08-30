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

    /// - Parameters:
    ///   - port: explicit port for a LAN connection (`ws://ip:port/`). Pass
    ///     `nil` for an internet/tunnel connection, where the scheme's
    ///     default port (443 for `wss`) applies and no port is embedded in
    ///     the URL — matches how a Cloudflare Tunnel hostname is reached.
    ///   - useTLS: `true` selects `wss://` (Cloudflare Tunnel terminates TLS
    ///     at its edge), `false` keeps the existing plain `ws://` LAN path.
    func connect(ip: String, port: Int? = nil, useTLS: Bool = false, password: String) {
        let session = URLSession(configuration: .default)
        self.session = session

        guard let url = Self.buildURL(ip: ip, port: port, useTLS: useTLS) else {
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
    static func buildURL(ip: String, port: Int?, useTLS: Bool) -> URL? {
        let scheme = useTLS ? "wss" : "ws"
        let host = port.map { "\(ip):\($0)" } ?? ip
        return URL(string: "\(scheme)://\(host)/")
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
