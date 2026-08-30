import XCTest
@testable import LiteDesk

final class ViewerClientURLBuildingTests: XCTestCase {
    func testLANConnectionUsesPlainWebSocketWithExplicitPort() {
        let url = ViewerClient.buildURL(ip: "192.168.1.24", port: 5900, useTLS: false)
        XCTAssertEqual(url?.absoluteString, "ws://192.168.1.24:5900/")
    }

    func testInternetTunnelConnectionUsesTLSWithNoExplicitPort() {
        let url = ViewerClient.buildURL(ip: "random-words.trycloudflare.com", port: nil, useTLS: true)
        XCTAssertEqual(url?.absoluteString, "wss://random-words.trycloudflare.com/")
    }

    func testDefaultsMatchLegacyLANBehavior() {
        let url = ViewerClient.buildURL(ip: "10.0.0.5", port: 5900, useTLS: false)
        XCTAssertEqual(url?.scheme, "ws")
        XCTAssertEqual(url?.port, 5900)
    }
}
