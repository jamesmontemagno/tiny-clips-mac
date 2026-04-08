import AppKit
import AVFoundation
import CoreGraphics
import ImageIO
import QuartzCore

struct MouseClickEvent: Sendable {
    let timeOffset: TimeInterval
    let globalLocation: CGPoint
}

private struct MappedMouseClickEvent: Sendable {
    let timeOffset: TimeInterval
    let point: CGPoint
}

private enum MouseClickPulse {
    static let duration: TimeInterval = 0.45
    static let baseRadius: CGFloat = 12
    static let expansion: CGFloat = 14
    static let lineWidth: CGFloat = 3
    static let maxOpacity: CGFloat = 0.8
}

@MainActor
final class MouseClickMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var startTimestamp: TimeInterval = 0
    private var events: [MouseClickEvent] = []

    func start() {
        stop()
        startTimestamp = ProcessInfo.processInfo.systemUptime
        events = []

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            self?.record(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            self?.record(event)
            return event
        }
    }

    @discardableResult
    func stop() -> [MouseClickEvent] {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }

        let captured = events
        events = []
        return captured
    }

    private func record(_ event: NSEvent) {
        let offset = max(0, event.timestamp - startTimestamp)
        let location = NSEvent.mouseLocation
        events.append(MouseClickEvent(timeOffset: offset, globalLocation: location))
    }
}

enum MouseClickOverlayProcessor {
    static func overlayOnVideo(
        sourceURL: URL,
        region: CaptureRegion,
        events: [MouseClickEvent],
        outputURL: URL
    ) async throws -> URL {
        let mappedEvents = mapMouseClickEvents(events, for: region)
        guard !mappedEvents.isEmpty else {
            return sourceURL
        }

        let asset = AVURLAsset(url: sourceURL)
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            return sourceURL
        }

        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return sourceURL
        }

        try compositionVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: videoTrack, at: .zero)
        compositionVideoTrack.preferredTransform = videoTrack.preferredTransform

        for audioTrack in asset.tracks(withMediaType: .audio) {
            if let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                try compositionAudioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: audioTrack, at: .zero)
            }
        }

        let transformedSize = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
        let renderSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 60)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        layerInstruction.setTransform(videoTrack.preferredTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.isGeometryFlipped = true

        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.addSublayer(videoLayer)

        let clickColor = NSColor.white.withAlphaComponent(0.9).cgColor

        for event in mappedEvents where event.timeOffset <= asset.duration.seconds {
            let ringLayer = CAShapeLayer()
            let diameter: CGFloat = 32
            ringLayer.path = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: diameter, height: diameter), transform: nil)
            ringLayer.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
            ringLayer.position = event.point
            ringLayer.fillColor = NSColor.clear.cgColor
            ringLayer.strokeColor = clickColor
            ringLayer.lineWidth = 3
            ringLayer.opacity = 0

            let pulse = CAAnimationGroup()
            pulse.beginTime = AVCoreAnimationBeginTimeAtZero + event.timeOffset
            pulse.duration = MouseClickPulse.duration
            pulse.isRemovedOnCompletion = true

            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = [0, 0.85, 0]
            opacity.keyTimes = [0, 0.2, 1]

            let scale = CAKeyframeAnimation(keyPath: "transform.scale")
            scale.values = [0.65, 1.05, 1.35]
            scale.keyTimes = [0, 0.35, 1]

            pulse.animations = [opacity, scale]
            ringLayer.add(pulse, forKey: "mouse-click-pulse")

            parentLayer.addSublayer(ringLayer)
        }

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parentLayer)

        try? FileManager.default.removeItem(at: outputURL)

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            return sourceURL
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.videoComposition = videoComposition
        exportSession.shouldOptimizeForNetworkUse = true

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            exportSession.exportAsynchronously {
                switch exportSession.status {
                case .completed:
                    continuation.resume(returning: ())
                case .failed, .cancelled:
                    continuation.resume(throwing: exportSession.error ?? CaptureError.saveFailed)
                default:
                    continuation.resume(throwing: CaptureError.saveFailed)
                }
            }
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: sourceURL)
        }
        return outputURL
    }

    static func loadGifCaptureData(from url: URL) throws -> GifCaptureData {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw CaptureError.saveFailed
        }

        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else {
            throw CaptureError.noFrames
        }

        var frames: [CGImage] = []
        frames.reserveCapacity(frameCount)

        var totalDelay = 0.0
        for index in 0..<frameCount {
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            frames.append(image)

            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gifProperties = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = (gifProperties?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                ?? (gifProperties?[kCGImagePropertyGIFDelayTime] as? Double)
                ?? 0.1
            totalDelay += max(0.01, delay)
        }

        guard !frames.isEmpty else {
            throw CaptureError.noFrames
        }

        let averageDelay = totalDelay / Double(frames.count)
        return GifCaptureData(frames: frames, frameDelay: averageDelay, maxWidth: CGFloat(frames[0].width))
    }

    static func overlayOnGif(
        gifData: GifCaptureData,
        region: CaptureRegion,
        events: [MouseClickEvent]
    ) -> GifCaptureData {
        let mappedEvents = mapMouseClickEvents(events, for: region)
        guard !mappedEvents.isEmpty else {
            return gifData
        }

        var processedFrames: [CGImage] = []
        processedFrames.reserveCapacity(gifData.frames.count)

        for (index, frame) in gifData.frames.enumerated() {
            let frameTime = Double(index) * gifData.frameDelay
            processedFrames.append(drawMouseClickPulseOverlay(on: frame, at: frameTime, events: mappedEvents))
        }

        return GifCaptureData(frames: processedFrames, frameDelay: gifData.frameDelay, maxWidth: gifData.maxWidth)
    }

    private static func drawMouseClickPulseOverlay(
        on image: CGImage,
        at frameTime: TimeInterval,
        events: [MappedMouseClickEvent]
    ) -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return image
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.setBlendMode(.normal)

        for event in events {
            let elapsed = frameTime - event.timeOffset
            guard elapsed >= 0, elapsed <= MouseClickPulse.duration else { continue }

            let progress = elapsed / MouseClickPulse.duration
            let alpha = max(0, (1 - progress) * MouseClickPulse.maxOpacity)
            let radius = MouseClickPulse.baseRadius + (MouseClickPulse.expansion * progress)

            context.setStrokeColor(NSColor.white.withAlphaComponent(alpha).cgColor)
            context.setLineWidth(MouseClickPulse.lineWidth)

            let centerY = CGFloat(image.height) - event.point.y
            let circleRect = CGRect(
                x: event.point.x - radius,
                y: centerY - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.strokeEllipse(in: circleRect)
        }

        return context.makeImage() ?? image
    }

    private static func mapMouseClickEvents(_ events: [MouseClickEvent], for region: CaptureRegion) -> [MappedMouseClickEvent] {
        events.compactMap { event in
            guard let point = capturePoint(for: event.globalLocation, in: region) else {
                return nil
            }
            return MappedMouseClickEvent(timeOffset: event.timeOffset, point: point)
        }
    }

    private static func capturePoint(for globalPoint: CGPoint, in region: CaptureRegion) -> CGPoint? {
        guard let screen = screen(for: region.displayID) else {
            return nil
        }

        let localX = globalPoint.x - screen.frame.minX
        let localY = screen.frame.maxY - globalPoint.y
        let localPoint = CGPoint(x: localX, y: localY)

        guard region.sourceRect.contains(localPoint) else {
            return nil
        }

        let relativeX = (localX - region.sourceRect.minX) * region.scaleFactor
        let relativeY = (localY - region.sourceRect.minY) * region.scaleFactor
        return CGPoint(x: relativeX, y: relativeY)
    }

    private static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let candidateID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                return false
            }
            return candidateID == displayID
        }
    }
}
