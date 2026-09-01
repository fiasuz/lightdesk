import ScreenCaptureKit
import CoreImage
import CoreMedia
import AppKit

/// Captures the primary display only, at ~30fps, pushing JPEG-encoded frames out
/// via `onFrame`. Deliberately started/stopped by the caller (HostSession) only
/// while a viewer is connected, rather than continuously — an efficiency win
/// over the old Electron app, which captured whenever host mode was "on".
final class ScreenCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private let processingQueue = DispatchQueue(label: "com.litedesk.capture")
    private let ciContext = CIContext(options: [.workingColorSpace: NSNull()])
    private let jpegQuality: Double = 0.5

    var onFrame: ((Data) -> Void)?
    var onError: ((String) -> Void)?

    func start() {
        guard PermissionsChecker.hasScreenRecordingAccess() else {
            onError?("Ekranni yozib olish ruxsati berilmagan (Tizim sozlamalari > Maxfiylik va xavfsizlik > Ekranni yozib olish).")
            return
        }
        Task {
            do {
                let content = try await SCShareableContent.current
                let mainDisplayID = CGMainDisplayID()
                guard let display = content.displays.first(where: { $0.displayID == mainDisplayID })
                    ?? content.displays.first else {
                    onError?("Asosiy ekran topilmadi")
                    return
                }

                let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                let config = SCStreamConfiguration()
                config.width = display.width
                config.height = display.height
                config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.showsCursor = true
                config.queueDepth = 3

                let stream = SCStream(filter: filter, configuration: config, delegate: self)
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: processingQueue)
                try await stream.startCapture()
                self.stream = stream
            } catch {
                onError?(error.localizedDescription)
            }
        }
    }

    func stop() {
        guard let activeStream = stream else { return }
        stream = nil
        Task {
            try? await activeStream.stopCapture()
        }
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .screen else { return }
        guard sampleBuffer.isValid, CMSampleBufferGetNumSamples(sampleBuffer) > 0 else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        guard let jpegData = JPEGEncoder.encode(cgImage: cgImage, quality: jpegQuality) else { return }
        onFrame?(jpegData)
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onError?(error.localizedDescription)
    }
}
