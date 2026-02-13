import ScreenCaptureKit
import ImageIO
import UniformTypeIdentifiers

struct ScreenshotCapture {
    static func capture(region: CaptureRegion) async throws -> URL {
        let filter = try await region.makeFilter()
        let config = region.makeStreamConfig()
        config.showsCursor = false

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

        let url = SaveService.shared.generateURL(for: .screenshot)

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw CaptureError.saveFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CaptureError.saveFailed
        }

        return url
    }
}
