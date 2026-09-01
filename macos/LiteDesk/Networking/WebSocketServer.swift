import Foundation
import Network
import CryptoKit

/// Hand-rolled RFC 6455 WebSocket server on top of Network.framework, since
/// Foundation only gives a WebSocket *client* on macOS (URLSessionWebSocketTask).
/// Scope matches the current app exactly: one authenticated viewer at a time,
/// plain-text password auth, no TLS.
final class WebSocketServer {
    enum ServerError: Error, LocalizedError {
        case invalidPort
        case listenerFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidPort: return "Noto'g'ri port"
            case .listenerFailed(let msg): return msg
            }
        }
    }

    private final class ClientConnection {
        let connection: NWConnection
        var handshakeBuffer = Data()
        var handshakeComplete = false
        var authenticated = false
        /// Password matched but the host hasn't approved or declined yet —
        /// blocks re-processing further "auth" messages from this client
        /// while its request sits in front of the host (see `handleAuth`).
        var awaitingApproval = false
        let decoder = WebSocketFrameDecoder()

        init(connection: NWConnection) {
            self.connection = connection
        }
    }

    private var listener: NWListener?
    private var pendingConnections: [ObjectIdentifier: ClientConnection] = [:]
    private var viewer: ClientConnection?
    /// The client whose password matched and is now waiting on the host's
    /// approve/decline decision (see `onConnectionRequest`). Counts as
    /// occupying the single connection slot, same as `viewer`.
    private var pendingApproval: ClientConnection?
    private var password: String = ""
    private let queue = DispatchQueue(label: "com.litedesk.wsserver")

    // Internet-facing exposure (via a Cloudflare Tunnel) makes the PIN
    // reachable from anyone, not just the LAN — track failed attempts per
    // remote IP and temporarily lock out repeat offenders.
    private struct AuthAttemptState {
        var failureCount = 0
        var windowStart = Date()
        var blockedUntil: Date?
    }
    private var authAttempts: [String: AuthAttemptState] = [:]
    private let maxAuthFailures = 5
    private let authFailureWindow: TimeInterval = 300
    private let authBlockDuration: TimeInterval = 300

    var onViewerConnected: (() -> Void)?
    var onViewerDisconnected: (() -> Void)?
    /// Fired once a connecting client's password checks out, carrying its
    /// remote IP (nil if it couldn't be determined) — the host must call
    /// `approveConnection()` or `declineConnection()` in response before the
    /// session actually starts.
    var onConnectionRequest: ((String?) -> Void)?
    /// Fired if the client awaiting approval disconnects before the host
    /// responds, so the host UI can dismiss the prompt on its own.
    var onConnectionRequestCancelled: (() -> Void)?
    var onMouseMessage: ((MouseMessage) -> Void)?
    var onKeyMessage: ((KeyMessage) -> Void)?
    var onPongMessage: ((Double) -> Void)?
    var onError: ((String) -> Void)?

    /// Called to obtain the width/height reported in auth-ok. Point-space on macOS
    /// (see plan: this value is not consumed by the viewer's rendering path today,
    /// so its coordinate space is a platform-internal detail, not a wire contract).
    var screenSizeProvider: (() -> (width: Int, height: Int))?

    func start(port: UInt16, password: String) throws {
        self.password = password
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw ServerError.invalidPort }

        let listener: NWListener
        do {
            listener = try NWListener(using: .tcp, on: nwPort)
        } catch {
            throw ServerError.listenerFailed(error.localizedDescription)
        }

        listener.newConnectionHandler = { [weak self] conn in
            self?.handleNewConnection(conn)
        }
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                self?.onError?(error.localizedDescription)
            }
        }
        listener.start(queue: queue)
        self.listener = listener
        WebSocketServer.debugLog("SERVER START on port \(port)")
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.viewer?.connection.cancel()
            self.viewer = nil
            self.pendingApproval?.connection.cancel()
            self.pendingApproval = nil
            for (_, client) in self.pendingConnections { client.connection.cancel() }
            self.pendingConnections.removeAll()
            self.listener?.cancel()
            self.listener = nil
        }
    }

    /// The host approved the connection currently awaiting a decision —
    /// finishes what `handleAuth` used to do immediately: mark it as the
    /// viewer, send `auth-ok`, and let capture start.
    func approveConnection() {
        queue.async { [weak self] in
            guard let self, let client = self.pendingApproval else { return }
            self.pendingApproval = nil
            client.authenticated = true
            self.viewer = client

            let size = self.screenSizeProvider?() ?? (width: 0, height: 0)
            let ok = AuthOkMessage(width: size.width, height: size.height)
            if let data = try? JSONEncoder().encode(ok) {
                let frame = WebSocketFrameEncoder.encodeText(data)
                client.connection.send(content: frame, completion: .contentProcessed { _ in })
            }
            self.onViewerConnected?()
        }
    }

    /// The host declined the connection currently awaiting a decision.
    /// Reuses `auth-fail` — a viewer already knows how to render it as a
    /// rejected connection attempt — rather than adding a new wire message
    /// that older/other-platform viewers wouldn't understand.
    func declineConnection() {
        queue.async { [weak self] in
            guard let self, let client = self.pendingApproval else { return }
            self.pendingApproval = nil
            let fail = AuthFailMessage()
            guard let data = try? JSONEncoder().encode(fail) else {
                client.connection.cancel()
                return
            }
            let frame = WebSocketFrameEncoder.encodeText(data)
            client.connection.send(content: frame, completion: .contentProcessed { _ in
                client.connection.cancel()
            })
        }
    }

    func sendFrame(_ jpegData: Data) {
        queue.async { [weak self] in
            guard let self, let viewer = self.viewer, viewer.authenticated else { return }
            let frame = WebSocketFrameEncoder.encodeBinary(jpegData)
            viewer.connection.send(content: frame, completion: .contentProcessed { _ in })
        }
    }

    /// Sends a ping carrying the current time; the viewer echoes it back in a
    /// "pong" (see `handleText`), letting `onPongMessage` report round-trip
    /// latency for the live session stats.
    func sendPing() {
        queue.async { [weak self] in
            guard let self, let viewer = self.viewer, viewer.authenticated else { return }
            let ping = PingMessage(ts: Date().timeIntervalSince1970)
            guard let data = try? JSONEncoder().encode(ping) else { return }
            let frame = WebSocketFrameEncoder.encodeText(data)
            viewer.connection.send(content: frame, completion: .contentProcessed { _ in })
        }
    }

    // MARK: - Connection lifecycle

    private func handleNewConnection(_ conn: NWConnection) {
        if let ip = Self.remoteIP(for: conn), isBlocked(ip: ip) {
            conn.cancel()
            return
        }
        let client = ClientConnection(connection: conn)
        pendingConnections[ObjectIdentifier(conn)] = client
        conn.stateUpdateHandler = { [weak self, weak client] state in
            guard let self, let client else { return }
            switch state {
            case .ready:
                self.receiveHandshake(client)
            case .failed, .cancelled:
                self.cleanup(client)
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    private func cleanup(_ client: ClientConnection) {
        pendingConnections.removeValue(forKey: ObjectIdentifier(client.connection))
        if pendingApproval === client {
            pendingApproval = nil
            onConnectionRequestCancelled?()
        }
        if viewer === client {
            viewer = nil
            onViewerDisconnected?()
        }
    }

    // MARK: - HTTP upgrade handshake

    private func receiveHandshake(_ client: ClientConnection) {
        client.connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak client] data, _, isComplete, error in
            guard let self, let client else { return }
            if let data, !data.isEmpty {
                client.handshakeBuffer.append(data)
                let terminator = Data("\r\n\r\n".utf8)
                if let range = client.handshakeBuffer.range(of: terminator) {
                    let headerData = Data(client.handshakeBuffer[..<range.upperBound])
                    let rest = Data(client.handshakeBuffer[range.upperBound...])
                    client.handshakeBuffer.removeAll()
                    client.handshakeComplete = true
                    self.completeHandshake(client, headerData: headerData)
                    if !rest.isEmpty {
                        self.handleFrameData(client, rest)
                    }
                    self.receiveFrames(client)
                    return
                }
            }
            if let error {
                _ = error
                self.cleanup(client)
                return
            }
            if isComplete {
                self.cleanup(client)
                return
            }
            self.receiveHandshake(client)
        }
    }

    private func completeHandshake(_ client: ClientConnection, headerData: Data) {
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            client.connection.cancel()
            return
        }
        let lines = headerString.components(separatedBy: "\r\n")
        var secKey: String?
        for line in lines {
            if let range = line.range(of: "Sec-WebSocket-Key:", options: .caseInsensitive) {
                secKey = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            }
        }
        guard let key = secKey else {
            client.connection.cancel()
            return
        }

        let acceptKey = Self.computeAcceptKey(key)
        let response = "HTTP/1.1 101 Switching Protocols\r\n"
            + "Upgrade: websocket\r\n"
            + "Connection: Upgrade\r\n"
            + "Sec-WebSocket-Accept: \(acceptKey)\r\n\r\n"

        client.connection.send(content: response.data(using: .utf8), completion: .contentProcessed { [weak self, weak client] error in
            guard let self, let client else { return }
            if error != nil {
                self.cleanup(client)
                return
            }
            if self.viewer != nil || self.pendingApproval != nil {
                // Only one connection slot at a time — awaiting approval counts as
                // occupying it too. Reject with a proper close frame, matching the
                // Electron app's socket.close(1000, 'busy').
                let closeFrame = WebSocketFrameEncoder.encodeClose(code: 1000, reason: "busy")
                client.connection.send(content: closeFrame, completion: .contentProcessed { _ in
                    client.connection.cancel()
                })
                self.pendingConnections.removeValue(forKey: ObjectIdentifier(client.connection))
            }
        })
    }

    private static func computeAcceptKey(_ key: String) -> String {
        let guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let digest = Insecure.SHA1.hash(data: Data((key + guid).utf8))
        return Data(digest).base64EncodedString()
    }

    // MARK: - Frame stream

    private func receiveFrames(_ client: ClientConnection) {
        client.connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak client] data, _, isComplete, error in
            guard let self, let client else { return }
            if let data, !data.isEmpty {
                self.handleFrameData(client, data)
            }
            if error != nil {
                self.cleanup(client)
                return
            }
            if isComplete {
                self.cleanup(client)
                return
            }
            self.receiveFrames(client)
        }
    }

    private func handleFrameData(_ client: ClientConnection, _ data: Data) {
        do {
            let frames = try client.decoder.feed(data)
            for frame in frames {
                handle(frame: frame, client: client)
            }
        } catch {
            client.connection.cancel()
        }
    }

    private func handle(frame: WebSocketFrame, client: ClientConnection) {
        switch frame.opcode {
        case .text:
            handleText(frame.payload, client: client)
        case .close:
            client.connection.cancel()
        case .ping:
            let pong = WebSocketFrameEncoder.encode(opcode: .pong, payload: frame.payload)
            client.connection.send(content: pong, completion: .contentProcessed { _ in })
        case .binary, .continuation, .pong:
            break
        }
    }

    private func handleText(_ payload: Data, client: ClientConnection) {
        guard client.authenticated else {
            handleAuth(payload, client: client)
            return
        }
        if let envelope = try? JSONDecoder().decode(TypeEnvelope.self, from: payload) {
            switch envelope.type {
            case "ping":
                if let ping = try? JSONDecoder().decode(PingMessage.self, from: payload) {
                    replyPong(ts: ping.ts, client: client)
                }
                return
            case "pong":
                if let pong = try? JSONDecoder().decode(PongMessage.self, from: payload) {
                    onPongMessage?(pong.ts)
                }
                return
            default:
                break
            }
        }
        // TEMP DIAGNOSTIC — remove once the live-move bug is root-caused.
        WebSocketServer.debugLog("RECV \(String(data: payload, encoding: .utf8) ?? "<non-utf8>")")
        if let message = MouseMessage.parse(payload) {
            onMouseMessage?(message)
        } else if let message = KeyMessage.parse(payload) {
            onKeyMessage?(message)
        } else {
            WebSocketServer.debugLog("PARSE FAILED for above payload")
        }
    }

    private func replyPong(ts: Double, client: ClientConnection) {
        let pong = PongMessage(ts: ts)
        guard let data = try? JSONEncoder().encode(pong) else { return }
        let frame = WebSocketFrameEncoder.encodeText(data)
        client.connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    // TEMP DIAGNOSTIC — remove once the live-move bug is root-caused.
    static func debugLog(_ line: String) {
        // /tmp, not ~/Desktop: Desktop/Documents/Downloads are TCC-protected
        // on macOS 10.15+, so a non-sandboxed app writing there without an
        // explicit user-granted bookmark either prompts or silently fails —
        // exactly what made the log file never show up.
        let path = "/tmp/litedesk-host-debug.log"
        let stamp = ISO8601DateFormatter().string(from: Date())
        let entry = "\(stamp) \(line)\n"
        if let data = entry.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: path), let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
    }

    private func handleAuth(_ payload: Data, client: ClientConnection) {
        guard !client.awaitingApproval else { return }
        guard let envelope = try? JSONDecoder().decode(TypeEnvelope.self, from: payload), envelope.type == "auth" else {
            return
        }
        guard let auth = try? JSONDecoder().decode(AuthMessage.self, from: payload) else { return }

        let ip = Self.remoteIP(for: client.connection)

        guard auth.password == password else {
            if let ip { recordAuthFailure(ip: ip) }
            // Small artificial delay to slow down naive brute-force loops
            // now that this port may be reachable from the whole internet
            // (via a Cloudflare Tunnel), not just the LAN.
            queue.asyncAfter(deadline: .now() + 0.5) { [weak client] in
                guard let client else { return }
                let fail = AuthFailMessage()
                if let data = try? JSONEncoder().encode(fail) {
                    let frame = WebSocketFrameEncoder.encodeText(data)
                    client.connection.send(content: frame, completion: .contentProcessed { _ in
                        client.connection.cancel()
                    })
                }
            }
            return
        }

        if let ip { authAttempts.removeValue(forKey: ip) }

        // Password matches, but don't finish the connection yet — park it
        // and let the host approve or decline first (see `approveConnection`
        // / `declineConnection`).
        client.awaitingApproval = true
        pendingConnections.removeValue(forKey: ObjectIdentifier(client.connection))
        pendingApproval = client
        onConnectionRequest?(ip)
    }

    // MARK: - Brute-force protection

    private static func remoteIP(for connection: NWConnection) -> String? {
        guard case let .hostPort(host, _) = connection.endpoint else { return nil }
        return "\(host)"
    }

    private func isBlocked(ip: String) -> Bool {
        guard let state = authAttempts[ip], let blockedUntil = state.blockedUntil else { return false }
        if Date() < blockedUntil {
            return true
        }
        authAttempts.removeValue(forKey: ip)
        return false
    }

    private func recordAuthFailure(ip: String) {
        var state = authAttempts[ip] ?? AuthAttemptState()
        if Date().timeIntervalSince(state.windowStart) > authFailureWindow {
            state = AuthAttemptState()
        }
        state.failureCount += 1
        if state.failureCount >= maxAuthFailures {
            state.blockedUntil = Date().addingTimeInterval(authBlockDuration)
        }
        authAttempts[ip] = state
    }
}
