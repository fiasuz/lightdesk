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

    func testSecondViewerIsRejectedAsBusy() throws {
        let server = WebSocketServer()
        server.screenSizeProvider = { () in (width: 100, height: 100) }
        let port = randomPort()
        try server.start(port: port, password: "secret123")
        defer { server.stop() }

        let firstConnected = expectation(description: "first viewer connected")
        server.onViewerConnected = { firstConnected.fulfill() }

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
}
