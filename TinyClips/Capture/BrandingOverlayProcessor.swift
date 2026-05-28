import AppKit
import AVFoundation
import CoreGraphics
import QuartzCore

// MARK: - Branding Overlay Processor

/// Renders a "Captured on Tiny Clips" watermark in the bottom-right corner of
/// screenshots, video recordings, and GIFs.
enum BrandingOverlayProcessor {
    private static let overlayText = "Captured on Tiny Clips"

    // MARK: - Screenshot / Image

    /// Composites the branding overlay onto a CGImage and returns the result.
    static func applyToImage(_ image: CGImage) -> CGImage {
        let width = image.width
        let height = image.height

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return image }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        drawTextOverlay(in: context, width: width, height: height)
        return context.makeImage() ?? image
    }

    // MARK: - GIF

    /// Composites the branding overlay onto every frame of a GIF.
    static func applyToGifData(_ gifData: GifCaptureData) -> GifCaptureData {
        guard !gifData.frames.isEmpty else { return gifData }
        let processedFrames = gifData.frames.map { applyToImage($0) }
        return GifCaptureData(frames: processedFrames, frameDelay: gifData.frameDelay, maxWidth: gifData.maxWidth)
    }

    // MARK: - Video

    /// Burns the branding overlay into a video file using AVVideoComposition and
    /// CoreAnimation layers, writing the result to `outputURL`.
    static func overlayOnVideo(
        sourceURL: URL,
        outputURL: URL,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        onProgress?(0.1)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            return sourceURL
        }

        let assetDuration = try await asset.load(.duration)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        onProgress?(0.25)

        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { return sourceURL }

        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: assetDuration),
            of: videoTrack,
            at: .zero
        )
        compositionVideoTrack.preferredTransform = preferredTransform

        for audioTrack in try await asset.loadTracks(withMediaType: .audio) {
            if let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) {
                try compositionAudioTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: assetDuration),
                    of: audioTrack,
                    at: .zero
                )
            }
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let transformedSize = naturalSize.applying(preferredTransform)
        let renderSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
        let sourceTimescale = max(30, Int32(nominalFrameRate.rounded(.up)))
        videoComposition.frameDuration = CMTime(value: 1, timescale: sourceTimescale)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: assetDuration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        layerInstruction.setTransform(preferredTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        // Build layer tree for CoreAnimation overlay tool.
        // parentLayer.isGeometryFlipped = true means y=0 is at the top (matching
        // AVFoundation's expectations for the animation tool).
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.isGeometryFlipped = true

        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.addSublayer(videoLayer)

        addBrandingLayer(to: parentLayer, renderSize: renderSize)

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        try? FileManager.default.removeItem(at: outputURL)

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            return sourceURL
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.videoComposition = videoComposition
        exportSession.shouldOptimizeForNetworkUse = true

        onProgress?(0.8)
        try await exportSession.export(to: outputURL, as: .mp4)

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: sourceURL)
        }
        onProgress?(1.0)
        return outputURL
    }

    // MARK: - Private helpers

    /// Adds static CALayer sublayers for the branding badge to `parentLayer`.
    ///
    /// `parentLayer.isGeometryFlipped = true`, so (0,0) is the top-left corner and
    /// (renderSize.width, renderSize.height) is the bottom-right corner.
    private static func addBrandingLayer(to parentLayer: CALayer, renderSize: CGSize) {
        let (bgRect, paddingH, bgHeight) = badgeGeometry(for: renderSize.height)

        // Position badge at the bottom-right.
        let bgX = renderSize.width - bgRect.width - bgRect.origin.x
        let bgY = renderSize.height - bgRect.height - bgRect.origin.y
        let finalBgRect = CGRect(x: bgX, y: bgY, width: bgRect.width, height: bgHeight)

        let backgroundLayer = CALayer()
        backgroundLayer.frame = finalBgRect
        backgroundLayer.backgroundColor = NSColor.black.withAlphaComponent(0.5).cgColor
        backgroundLayer.cornerRadius = bgHeight / 3
        parentLayer.addSublayer(backgroundLayer)

        let fontSize = badgeFontSize(for: renderSize.height)
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let attrString = NSAttributedString(
            string: overlayText,
            attributes: [.font: font, .foregroundColor: NSColor.white]
        )
        let textSize = attrString.size()

        // Center text vertically within the background pill.
        let textX = bgX + paddingH
        let textY = bgY + (bgHeight - textSize.height) / 2
        let textLayerFrame = CGRect(x: textX, y: textY, width: textSize.width, height: textSize.height)

        let textLayer = CATextLayer()
        textLayer.string = attrString
        textLayer.frame = textLayerFrame
        textLayer.contentsScale = 2.0
        textLayer.isWrapped = false
        parentLayer.addSublayer(textLayer)
    }

    /// Draws the branding badge directly into a CGContext.
    ///
    /// CGContext uses a bottom-left origin (y=0 at bottom), so the badge is placed
    /// with a small margin from the right and bottom edges.
    private static func drawTextOverlay(in context: CGContext, width: Int, height: Int) {
        let (bgRect, paddingH, bgHeight) = badgeGeometry(for: CGFloat(height))

        // CGContext: y=0 is bottom. Place badge in the bottom-right corner.
        let bgX = CGFloat(width) - bgRect.width - bgRect.origin.x
        let bgY = bgRect.origin.y  // margin from bottom edge
        let finalBgRect = CGRect(x: bgX, y: bgY, width: bgRect.width, height: bgHeight)

        // Draw rounded-rect background.
        let cornerRadius = bgHeight / 3
        let path = CGPath(roundedRect: finalBgRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        context.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
        context.addPath(path)
        context.fillPath()

        // Draw text using a flipped coordinate system (NSAttributedString expects top-left origin).
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        // In flipped coords: y=0 is top, y=height is bottom.
        // Original bgY (from bottom) maps to flippedBgTop = height - bgY - bgHeight.
        let flippedBgTop = CGFloat(height) - bgY - bgHeight
        let fontSize = badgeFontSize(for: CGFloat(height))
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let attrString = NSAttributedString(
            string: overlayText,
            attributes: [.font: font, .foregroundColor: NSColor.white]
        )
        let textSize = attrString.size()

        // Center text vertically within the pill.
        let textX = bgX + paddingH
        let textY = flippedBgTop + (bgHeight - textSize.height) / 2
        attrString.draw(in: CGRect(x: textX, y: textY, width: textSize.width, height: textSize.height))

        context.restoreGState()
    }

    // MARK: - Badge geometry helpers

    /// Font size scaled proportionally to image height, clamped to a sensible range.
    private static func badgeFontSize(for imageHeight: CGFloat) -> CGFloat {
        max(12.0, min(28.0, imageHeight / 50.0))
    }

    /// Returns `(bgRect with origin=margin, paddingH, bgHeight)` for the given image height.
    /// `bgRect.origin` encodes the margin from the edge; actual placement x/y is computed by callers.
    private static func badgeGeometry(for imageHeight: CGFloat) -> (bgRect: CGRect, paddingH: CGFloat, bgHeight: CGFloat) {
        let fontSize = badgeFontSize(for: imageHeight)
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let textSize = NSAttributedString(
            string: overlayText,
            attributes: [.font: font, .foregroundColor: NSColor.white]
        ).size()

        let paddingH = fontSize * 0.7
        let paddingV = fontSize * 0.45
        let margin = fontSize

        let bgWidth = textSize.width + paddingH * 2
        let bgHeight = textSize.height + paddingV * 2

        // origin encodes the margin (distance from the nearest edge)
        let bgRect = CGRect(x: margin, y: margin, width: bgWidth, height: bgHeight)
        return (bgRect, paddingH, bgHeight)
    }
}
