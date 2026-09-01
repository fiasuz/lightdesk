import XCTest
@testable import LiteDesk

// End-to-end: a real WebSocketServer (NWListener-based, hand-rolled RFC6455)
// talking over actual loopback TCP to a real URLSessionWebSocketTask client —
// exercises the exact handshake/auth/frame path production code will use.
final class WebSocketServerAuthTests: XCTestCase {
    private func randomPort() -> UInt16 {
        UInt16.random(in: 20000...40000)
    }

    func testAuthSucceedsWithCorrectPassword() throws {
        let server = WebSocketServer()
        server.screenSizeProvider = { () in (width: 1920, height: 1080) }
        let port = randomPort()
        try server.start(port: port, password: "secret123")
        defer { server.stop() }

        let connectedExpectation = expectation(description: "viewer connected")
        server.onViewerConnected = { connectedExpectation.fulfill() }
        // A correct password only parks the connection — it doesn't finish
        // until the host approves it.
        server.onConnectionRequest = { _ in server.approveConnection() }

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)/")!)
        task.resume()
        defer { task.cancel(with: .normalClosure, reason: nil) }

        let authMessage = AuthMessage(password: "secret123")
        let authData = try JSONEncoder().encode(authMessage)
        task.send(.string(String(data: authData, encoding: .utf8)!)) { _ in }

        let authOkExpectation = expectation(description: "received auth-ok")
        var receivedWidth: Int?
        var receivedHeight: Int?

        func receiveOnce() {
            task.receive { result in
                if case .success(.string(let text)) = result,
                   let data = text.data(using: .utf8),
                   let ok = try? JSONDecoder().decode(AuthOkMessage.self, from: data) {
                    receivedWidth = ok.width
                    receivedHeight = ok.height
                    authOkExpectation.fulfill()
                }
            }
        }
        receiveOnce()

        wait(for: [connectedExpectation, authOkExpectation], timeout: 5.0)
        XCTAssertEqual(receivedWidth, 1920)
        XCTAssertEqual(receivedHeight, 1080)
    }

    func testAuthFailsWithWrongPassword() throws {
        let server = WebSocketServer()
        server.screenSizeProvider = { () in (width: 100, height: 100) }
        let port = randomPort()
        try server.start(port: port, password: "correct")
        defer { server.stop() }

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)/")!)
        task.resume()
        defer { task.cancel(with: .normalClosure, reason: nil) }

        let authMessage = AuthMessage(password: "wrong")
        let authData = try JSONEncoder().encode(authMessage)
        task.send(.string(String(data: authData, encoding: .utf8)!)) { _ in }

        let authFailExpectation = expectation(description: "received auth-fail")
        task.receive { result in
            if case .success(.string(let text)) = result,
               let data = text.data(using: .utf8),
               let envelope = try? JSONDecoder().decode(TypeEnvelope.self, from: data) {
                XCTAssertEqual(envelope.type, "auth-fail")
                authFailExpectation.fulfill()
            }
        }

        wait(for: [authFailExpectation], timeout: 5.0)
    }

    func testCorrectPasswordWaitsForHostApprovalBeforeAuthOk() throws {
        let server = WebSocketServer()
        server.screenSizeProvider = { () in (width: 100, height: 100) }
        let port = randomPort()
        try server.start(port: port, password: "secret123")
        defer { server.stop() }

        let requestExpectation = expectation(description: "connection request raised")
        server.onConnectionRequest = { _ in requestExpectation.fulfill() }
        // Fulfilled by `onViewerConnected` firing before we ever call
        // `approveConnection()` below — should never happen.
        let prematureConnectExpectation = expectation(description: "viewer connected before approval")
        prematureConnectExpectation.isInverted = true
        let connectedExpectation = expectation(description: "viewer connected after approval")
        server.onViewerConnected = {
            prematureConnectExpectation.fulfill()
            connectedExpectation.fulfill()
        }

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)/")!)
        task.resume()
        defer { task.cancel(with: .normalClosure, reason: nil) }

        let authMessage = AuthMessage(password: "secret123")
        let authData = try JSONEncoder().encode(authMessage)
        task.send(.string(String(data: authData, encoding: .utf8)!)) { _ in }

        // Nothing should arrive on the wire until the host decides.
        wait(for: [requestExpectation, prematureConnectExpectation], timeout: 0.5)

        server.approveConnection()
        wait(for: [connectedExpectation], timeout: 5.0)
    }

    func testHostCanDeclineAConnectionRequest() throws {
        let server = WebSocketServer()
        server.screenSizeProvider = { () in (width: 100, height: 100) }
        let port = randomPort()
        try server.start(port: port, password: "secret123")
        defer { server.stop() }

        let requestExpectation = expectation(description: "connection request raised")
        server.onConnectionRequest = { _ in
            server.declineConnection()
            requestExpectation.fulfill()
        }

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)/")!)
        task.resume()
        defer { task.cancel(with: .normalClosure, reason: nil) }

        let authMessage = AuthMessage(password: "secret123")
        let authData = try JSONEncoder().encode(authMessage)
        task.send(.string(String(data: authData, encoding: .utf8)!)) { _ in }
        wait(for: [requestExpectation], timeout: 5.0)

        let authFailExpectation = expectation(description: "received auth-fail after decline")
        task.receive { result in
            if case .success(.string(let text)) = result,
               let data = text.data(using: .utf8),
               let envelope = try? JSONDecoder().decode(TypeEnvelope.self, from: data) {
                XCTAssertEqual(envelope.type, "auth-fail")
                authFailExpectation.fulfill()
            }
        }
        wait(for: [authFailExpectation], timeout: 5.0)
    }

    func testSecondViewerIsRejectedAsBusy() throws {
        let server = WebSocketServer()
        server.screenSizeProvider = { () in (width: 100, height: 100) }
        let port = randomPort()
        try server.start(port: port, password: "secret123")
        defer { server.stop() }

        let firstConnected = expectation(description: "first viewer connected")
        server.onViewerConnected = { firstConnected.fulfill() }
        server.onConnectionRequest = { _ in server.approveConnection() }

        let session = URLSession(configuration: .default)
        let firstTask = session.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)/")!)
        firstTask.resume()
        defer { firstTask.cancel(with: .normalClosure, reason: nil) }

        let authMessage = AuthMessage(password: "secret123")
        let authData = try JSONEncoder().encode(authMessage)
        firstTask.send(.string(String(data: authData, encoding: .utf8)!)) { _ in }
        firstTask.receive { _ in } // drain the auth-ok

        wait(for: [firstConnected], timeout: 5.0)

        let secondTask = session.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)/")!)
        secondTask.resume()
        defer { secondTask.cancel(with: .normalClosure, reason: nil) }

        let busyExpectation = expectation(description: "second connection closed as busy")
        func receiveUntilClosed() {
            secondTask.receive { result in
                switch result {
                case .failure:
                    busyExpectation.fulfill()
                case .success:
                    receiveUntilClosed()
                }
            }
        }
        receiveUntilClosed()

        wait(for: [busyExpectation], timeout: 5.0)
        XCTAssertEqual(secondTask.closeCode, .normalClosure)
    }

    // Now that the host may be reachable from the whole internet via a
    // Cloudflare Tunnel rather than only the LAN, repeated wrong-password
    // attempts from the same remote IP must eventually get locked out.
    func testRepeatedWrongPasswordAttemptsAreLockedOut() throws {
        let server = WebSocketServer()
        server.screenSizeProvider = { () in (width: 100, height: 100) }
        let port = randomPort()
        try server.start(port: port, password: "correct-horse-battery")
        defer { server.stop() }

        let session = URLSession(configuration: .default)

        func attemptWrongAuth() {
            let task = session.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)/")!)
            task.resume()

            let authMessage = AuthMessage(password: "nope")
            let authData = try! JSONEncoder().encode(authMessage)
            task.send(.string(String(data: authData, encoding: .utf8)!)) { _ in }

            let failedExpectation = expectation(description: "auth-fail received")
            task.receive { result in
                if case .success(.string(let text)) = result,
                   let data = text.data(using: .utf8),
                   let envelope = try? JSONDecoder().decode(TypeEnvelope.self, from: data),
                   envelope.type == "auth-fail" {
                    failedExpectation.fulfill()
                }
            }
            wait(for: [failedExpectation], timeout: 3.0)
            task.cancel(with: .normalClosure, reason: nil)
        }

        for _ in 0..<5 {
            attemptWrongAuth()
        }

        // The 6th connection attempt from the same IP should be rejected
        // outright — the server cancels it before ever completing the
        // WebSocket upgrade handshake.
        let blockedTask = session.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)/")!)
        blockedTask.resume()
        defer { blockedTask.cancel(with: .normalClosure, reason: nil) }

        let rejectedExpectation = expectation(description: "connection rejected due to lockout")
        blockedTask.receive { result in
            if case .failure = result {
                rejectedExpectation.fulfill()
            }
        }
        wait(for: [rejectedExpectation], timeout: 3.0)
    }
}
