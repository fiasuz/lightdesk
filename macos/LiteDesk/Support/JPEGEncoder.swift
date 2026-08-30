import AppKit
import CoreGraphics

// Direct analogue of the Electron app's canvas.toBlob('image/jpeg', 0.5) — a
// pure function so it's testable against a synthetic CGImage without a live
// screen-capture session.
enum JPEGEncoder {
    static func encode(cgImage: CGImage, quality: Double) -> Data? {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }
}
