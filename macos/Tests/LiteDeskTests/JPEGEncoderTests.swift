import XCTest
import CoreGraphics
import AppKit
@testable import LiteDesk

final class JPEGEncoderTests: XCTestCase {
    private func makeSyntheticCGImage(width: Int = 64, height: Int = 32) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
        return context.makeImage()!
    }

    func testEncodeProducesValidJPEGData() {
        let image = makeSyntheticCGImage()
        guard let data = JPEGEncoder.encode(cgImage: image, quality: 0.5) else {
            return XCTFail("expected JPEG data")
        }
        XCTAssertGreaterThan(data.count, 0)
        // JPEG files start with the SOI marker 0xFFD8.
        XCTAssertEqual(data.prefix(2), Data([0xFF, 0xD8]))
    }

    func testEncodedJPEGIsDecodableBackToTheSameDimensions() {
        let image = makeSyntheticCGImage(width: 100, height: 50)
        guard let data = JPEGEncoder.encode(cgImage: image, quality: 0.5),
              let decoded = NSBitmapImageRep(data: data) else {
            return XCTFail("expected round-trippable JPEG data")
        }
        XCTAssertEqual(decoded.pixelsWide, 100)
        XCTAssertEqual(decoded.pixelsHigh, 50)
    }

    func testHigherQualityProducesLargerOrEqualFileSize() {
        let image = makeSyntheticCGImage(width: 200, height: 200)
        guard let lowQuality = JPEGEncoder.encode(cgImage: image, quality: 0.1),
              let highQuality = JPEGEncoder.encode(cgImage: image, quality: 0.9) else {
            return XCTFail("expected JPEG data at both quality levels")
        }
        XCTAssertGreaterThanOrEqual(highQuality.count, lowQuality.count)
    }
}
