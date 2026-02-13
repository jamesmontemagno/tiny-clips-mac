import ScreenCaptureKit
import CoreMedia
import CoreImage
import ImageIO

class GifWriter: NSObject, @unchecked Sendable {
    private var stream: SCStream?
    private var frames: [CGImage] = []
    private var frameDelay: Double = 0.1
    private var maxWidth: CGFloat = 640
    private let processingQueue = DispatchQueue(label: "com.tinyclips.gif-processing")
    private let ciContext = CIContext()

    func start(region: CaptureRegion) async throws {
        let filter = try await region.makeFilter()
        let config = region.makeStreamConfig()

        let settings = CaptureSettings.shared
        let fps = settings.gifFrameRate
        self.frameDelay = 1.0 / fps
        self.maxWidth = CGFloat(settings.gifMaxWidth)

        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.showsCursor = true
        config.queueDepth = 5

        frames = []

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: processingQueue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop(outputURL: URL) async throws {
        try await stream?.stopCapture()
        stream = nil

        let capturedFrames = processingQueue.sync { self.frames }
        guard !capturedFrames.isEmpty else {
            throw CaptureError.noFrames
        }

        try writeGIF(frames: capturedFrames, to: outputURL)
    }

    private func writeGIF(frames: [CGImage], to url: URL) throws {
        let processedFrames: [CGImage]
        if CGFloat(frames[0].width) > maxWidth {
            let scale = maxWidth / CGFloat(frames[0].width)
            let newWidth = Int(maxWidth)
            let newHeight = Int(CGFloat(frames[0].height) * scale)
            let size = CGSize(width: newWidth, height: newHeight)
            processedFrames = frames.compactMap { downscale($0, to: size) }
        } else {
            processedFrames = frames
        }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            "com.compuserve.gif" as CFString,
            processedFrames.count,
            nil
        ) else {
            throw CaptureError.saveFailed
        }

        let gifProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount: 0,
            ],
        ]
        CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)

        for frame in processedFrames {
            let frameProperties: [String: Any] = [
                kCGImagePropertyGIFDictionary as String: [
                    kCGImagePropertyGIFDelayTime: frameDelay,
                ],
            ]
            CGImageDestinationAddImage(destination, frame, frameProperties as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw CaptureError.saveFailed
        }
    }

    private func downscale(_ image: CGImage, to size: CGSize) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return context.makeImage()
    }
}

extension GifWriter: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }

        frames.append(cgImage)
    }
}
