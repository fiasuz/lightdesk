import XCTest
@testable import LiteDesk

final class CloudflaredTunnelManagerTests: XCTestCase {
    func testExtractsURLFromRealisticCloudflaredBanner() {
        let banner = """
        2026-08-30T10:00:00Z INF Thank you for trying Cloudflare Tunnel. Doing so should be fairly simple!
        2026-08-30T10:00:01Z INF Requesting new quick Tunnel on trycloudflare.com...
        2026-08-30T10:00:02Z INF +--------------------------------------------------------------------------------------------+
        2026-08-30T10:00:02Z INF |  Your quick Tunnel has been created! Visit it at (it may take some time to be reachable):    |
        2026-08-30T10:00:02Z INF |  https://random-example-words.trycloudflare.com                                            |
        2026-08-30T10:00:02Z INF +--------------------------------------------------------------------------------------------+
        """
        XCTAssertEqual(
            CloudflaredTunnelManager.extractTunnelURL(from: banner),
            "https://random-example-words.trycloudflare.com"
        )
    }

    func testReturnsNilWhenNoURLPresentYet() {
        let partial = "2026-08-30T10:00:00Z INF Thank you for trying Cloudflare Tunnel.\n"
        XCTAssertNil(CloudflaredTunnelManager.extractTunnelURL(from: partial))
    }

    func testIgnoresUnrelatedHttpsURLs() {
        let text = "See https://developers.cloudflare.com/cloudflare-one/ for docs.\n"
        XCTAssertNil(CloudflaredTunnelManager.extractTunnelURL(from: text))
    }
}
