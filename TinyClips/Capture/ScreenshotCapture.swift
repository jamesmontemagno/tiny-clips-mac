import ScreenCaptureKit
import ImageIO
import UniformTypeIdentifiers

struct ScreenshotCapture {
    static func capture(region: CaptureRegion) async throws -> URL {
        let destinationURL = SaveService.shared.generateURL(for: .screenshot)
        return try await capture(region: region, outputURL: destinationURL)
    }

    static func capture(region: CaptureRegion, outputURL: URL) async throws -> URL {
        let filter = try await region.makeFilter()
        let config = region.makeStreamConfig()
        config.showsCursor = false

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

        let settings = CaptureSettings.shared
        let imageType = settings.imageFormat.utType
        let destinationProperties: [CFString: Any]
        if settings.imageFormat == .jpeg {
            destinationProperties = [kCGImageDestinationLossyCompressionQuality: settings.jpegQuality]
        } else {
            destinationProperties = [:]
        }

        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            imageType.identifier as CFString,
            1,
            nil
        ) else {
            throw CaptureError.saveFailed
        }
        CGImageDestinationAddImage(destination, image, destinationProperties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CaptureError.saveFailed
        }

        return outputURL
    }
}
