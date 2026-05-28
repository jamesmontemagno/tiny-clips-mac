import AppKit
import AVFoundation
import CoreGraphics
import CoreText
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

    /// Adds the branding badge as a single image-backed CALayer.
    ///
    /// We render the entire pill (background + text) into a CGImage rather than
    /// using CATextLayer, because AVVideoCompositionCoreAnimationTool frequently
    /// fails to render CATextLayer text reliably.
    ///
    /// `parentLayer.isGeometryFlipped = true`, so (0,0) is the top-left corner and
    /// (renderSize.width, renderSize.height) is the bottom-right corner.
    private static func addBrandingLayer(to parentLayer: CALayer, renderSize: CGSize) {
        let scale: CGFloat = 2.0
        let fontSize = badgeFontSize(for: renderSize.height)
        let ctFont = makeBadgeFont(size: fontSize)
        let textSize = measureBadgeText(font: ctFont)
        let (bgWidth, bgHeight, _, margin) = badgePillSize(textSize: textSize, fontSize: fontSize)

        guard let badgeImage = renderBadgeImage(width: bgWidth, height: bgHeight, fontSize: fontSize, scale: scale) else {
            return
        }

        let bgX = renderSize.width - bgWidth - margin
        let bgY = renderSize.height - bgHeight - margin

        let badgeLayer = CALayer()
        badgeLayer.frame = CGRect(x: bgX, y: bgY, width: bgWidth, height: bgHeight)
        badgeLayer.contents = badgeImage
        badgeLayer.contentsScale = scale
        badgeLayer.contentsGravity = .resize
        parentLayer.addSublayer(badgeLayer)
    }

    /// Renders the full pill+text badge to a CGImage at `scale` density.
    private static func renderBadgeImage(width: CGFloat, height: CGFloat, fontSize: CGFloat, scale: CGFloat) -> CGImage? {
        let pixelWidth = Int(ceil(width * scale))
        let pixelHeight = Int(ceil(height * scale))
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.scaleBy(x: scale, y: scale)
        drawBadge(in: context, rect: CGRect(x: 0, y: 0, width: width, height: height), fontSize: fontSize)
        return context.makeImage()
    }

    /// Draws the branding badge directly into a CGContext using Core Text
    /// (thread-safe, unlike NSString/TextKit which silently no-ops off main).
    ///
    /// CGContext uses a bottom-left origin (y=0 at bottom), so the badge is placed
    /// with a small margin from the right and bottom edges.
    private static func drawTextOverlay(in context: CGContext, width: Int, height: Int) {
        let fontSize = badgeFontSize(for: CGFloat(height))
        let ctFont = makeBadgeFont(size: fontSize)
        let textSize = measureBadgeText(font: ctFont)
        let (bgWidth, bgHeight, _, margin) = badgePillSize(textSize: textSize, fontSize: fontSize)

        let bgRect = CGRect(x: CGFloat(width) - bgWidth - margin, y: margin, width: bgWidth, height: bgHeight)
        drawBadge(in: context, rect: bgRect, fontSize: fontSize)
    }

    /// Shared primitive: draws the pill background and centered text into `rect`.
    private static func drawBadge(in context: CGContext, rect: CGRect, fontSize: CGFloat) {
        let ctFont = makeBadgeFont(size: fontSize)
        let (_, _, paddingH, _) = badgePillSize(textSize: measureBadgeText(font: ctFont), fontSize: fontSize)

        // Background pill.
        let cornerRadius = rect.height / 3
        let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        context.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
        context.addPath(path)
        context.fillPath()

        // Text.
        let attributes: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: ctFont,
            kCTForegroundColorAttributeName as NSAttributedString.Key: NSColor.white.cgColor,
        ]
        let attrString = NSAttributedString(string: overlayText, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString)

        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)

        let textX = rect.minX + paddingH
        let baselineY = rect.minY + (rect.height - (ascent + descent)) / 2 + descent

        context.saveGState()
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: textX, y: baselineY)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    // MARK: - Badge geometry helpers

    /// Font size scaled proportionally to image height, clamped to a sensible range.
    private static func badgeFontSize(for imageHeight: CGFloat) -> CGFloat {
        max(12.0, min(28.0, imageHeight / 50.0))
    }

    private static func makeBadgeFont(size: CGFloat) -> CTFont {
        CTFontCreateUIFontForLanguage(.system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }

    private static func measureBadgeText(font: CTFont) -> CGSize {
        let attrString = NSAttributedString(string: overlayText, attributes: [
            kCTFontAttributeName as NSAttributedString.Key: font,
        ])
        let line = CTLineCreateWithAttributedString(attrString)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        return CGSize(width: ceil(width), height: ceil(ascent + descent))
    }

    private static func badgePillSize(
        textSize: CGSize,
        fontSize: CGFloat
    ) -> (width: CGFloat, height: CGFloat, paddingH: CGFloat, margin: CGFloat) {
        let paddingH = fontSize * 0.7
        let paddingV = fontSize * 0.45
        let margin = fontSize
        return (textSize.width + paddingH * 2, textSize.height + paddingV * 2, paddingH, margin)
    }

    private static func badgeGeometry(for imageHeight: CGFloat) -> (bgRect: CGRect, paddingH: CGFloat, bgHeight: CGFloat) {
        let fontSize = badgeFontSize(for: imageHeight)
        let ctFont = makeBadgeFont(size: fontSize)
        let textSize = measureBadgeText(font: ctFont)
        let (bgWidth, bgHeight, paddingH, margin) = badgePillSize(textSize: textSize, fontSize: fontSize)
        let bgRect = CGRect(x: margin, y: margin, width: bgWidth, height: bgHeight)
        return (bgRect, paddingH, bgHeight)
    }
}
