import XCTest
@testable import LiteDesk

final class ViewerClientURLBuildingTests: XCTestCase {
    func testTunnelConnectionUsesTLSWithNoExplicitPort() {
        let url = ViewerClient.buildURL(host: "random-words.trycloudflare.com")
        XCTAssertEqual(url?.absoluteString, "wss://random-words.trycloudflare.com/")
    }
}
