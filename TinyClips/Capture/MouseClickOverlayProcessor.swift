import AppKit
import AVFoundation
import Carbon.HIToolbox
import CoreGraphics
import CoreText
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
        outputURL: URL,
        style: MouseClickOverlayStyle,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> URL {
        let mappedEvents = mapMouseClickEvents(events, for: region)
        guard !mappedEvents.isEmpty else {
            return sourceURL
        }

        let asset = AVURLAsset(url: sourceURL)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            return sourceURL
        }
        let assetDuration = try await asset.load(.duration)
        let videoPreferredTransform = try await videoTrack.load(.preferredTransform)

        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return sourceURL
        }

        try compositionVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: assetDuration), of: videoTrack, at: .zero)
        compositionVideoTrack.preferredTransform = videoPreferredTransform

        for audioTrack in try await asset.loadTracks(withMediaType: .audio) {
            if let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                try compositionAudioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: assetDuration), of: audioTrack, at: .zero)
            }
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let transformedSize = naturalSize.applying(videoPreferredTransform)
        let renderSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
        let sourceTimescale = max(30, Int32(nominalFrameRate.rounded(.up)))
        videoComposition.frameDuration = CMTime(value: 1, timescale: sourceTimescale)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: assetDuration)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        layerInstruction.setTransform(videoPreferredTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.isGeometryFlipped = true

        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.addSublayer(videoLayer)

        let clickColor = style.color.cgColor

        for event in mappedEvents where event.timeOffset <= assetDuration.seconds {
            let ringLayer = CAShapeLayer()
            let diameter = style.size
            ringLayer.path = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: diameter, height: diameter), transform: nil)
            ringLayer.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
            ringLayer.position = event.point
            ringLayer.fillColor = NSColor.clear.cgColor
            ringLayer.strokeColor = clickColor
            ringLayer.lineWidth = style.strokeWidth
            ringLayer.opacity = 0

            let pulse = CAAnimationGroup()
            pulse.beginTime = AVCoreAnimationBeginTimeAtZero + event.timeOffset
            pulse.duration = style.duration
            pulse.isRemovedOnCompletion = false
            pulse.fillMode = .both
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = [0, style.opacity, 0]
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

        try await exportSession.export(to: outputURL, as: .mp4)
        onProgress?(1.0)

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
        events: [MouseClickEvent],
        style: MouseClickOverlayStyle
    ) -> GifCaptureData {
        let mappedEvents = mapMouseClickEvents(events, for: region)
        guard !mappedEvents.isEmpty else {
            return gifData
        }

        var processedFrames: [CGImage] = []
        processedFrames.reserveCapacity(gifData.frames.count)

        for (index, frame) in gifData.frames.enumerated() {
            let frameTime = Double(index) * gifData.frameDelay
            processedFrames.append(drawMouseClickPulseOverlay(on: frame, at: frameTime, events: mappedEvents, style: style))
        }

        return GifCaptureData(frames: processedFrames, frameDelay: gifData.frameDelay, maxWidth: gifData.maxWidth)
    }

    private static func drawMouseClickPulseOverlay(
        on image: CGImage,
        at frameTime: TimeInterval,
        events: [MappedMouseClickEvent],
        style: MouseClickOverlayStyle
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
            guard elapsed >= 0, elapsed <= style.duration else { continue }

            let progress = elapsed / style.duration
            let alpha = max(0, (1 - progress) * style.opacity)
            let radius = (style.size / 2.0) + (style.size * 0.58 * progress)

            context.setStrokeColor(style.color.withAlphaComponent(alpha).cgColor)
            context.setLineWidth(style.strokeWidth)

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

struct KeyboardOverlayEvent: Sendable {
    let timeOffset: TimeInterval
    let label: String
    let keyToken: String
    let isModifierOnly: Bool
}

@MainActor
final class KeyboardEventMonitor {
    private var globalKeyDownMonitor: Any?
    private var localKeyDownMonitor: Any?
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var startTimestamp: TimeInterval = 0
    private var events: [KeyboardOverlayEvent] = []
    private var previousFlags: NSEvent.ModifierFlags = []

    func start() {
        stop()
        startTimestamp = ProcessInfo.processInfo.systemUptime
        events = []
        previousFlags = []

        globalKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.recordKeyDown(event)
        }
        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.recordKeyDown(event)
            return event
        }
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.recordFlagsChanged(event)
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.recordFlagsChanged(event)
            return event
        }
    }

    @discardableResult
    func stop() -> [KeyboardOverlayEvent] {
        if let globalKeyDownMonitor {
            NSEvent.removeMonitor(globalKeyDownMonitor)
            self.globalKeyDownMonitor = nil
        }
        if let localKeyDownMonitor {
            NSEvent.removeMonitor(localKeyDownMonitor)
            self.localKeyDownMonitor = nil
        }
        if let globalFlagsMonitor {
            NSEvent.removeMonitor(globalFlagsMonitor)
            self.globalFlagsMonitor = nil
        }
        if let localFlagsMonitor {
            NSEvent.removeMonitor(localFlagsMonitor)
            self.localFlagsMonitor = nil
        }

        let captured = events
        events = []
        previousFlags = []
        return captured
    }

    private func recordKeyDown(_ event: NSEvent) {
        let keyDisplay = keyDisplay(for: event)
        let keyToken = normalizedToken(from: keyDisplay)
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let label = formattedLabel(modifiers: flags, keyDisplay: keyDisplay)
        appendEvent(
            KeyboardOverlayEvent(
                timeOffset: max(0, event.timestamp - startTimestamp),
                label: label,
                keyToken: keyToken,
                isModifierOnly: false
            )
        )
    }

    private func recordFlagsChanged(_ event: NSEvent) {
        let tracked = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let newlyPressed = tracked.subtracting(previousFlags)
        previousFlags = tracked

        let ordered: [(NSEvent.ModifierFlags, String, String)] = [
            (.command, "⌘", "COMMAND"),
            (.shift, "⇧", "SHIFT"),
            (.option, "⌥", "OPTION"),
            (.control, "⌃", "CONTROL")
        ]

        for (flag, symbol, token) in ordered where newlyPressed.contains(flag) {
            appendEvent(
                KeyboardOverlayEvent(
                    timeOffset: max(0, event.timestamp - startTimestamp),
                    label: symbol,
                    keyToken: token,
                    isModifierOnly: true
                )
            )
        }
    }

    private func formattedLabel(modifiers: NSEvent.ModifierFlags, keyDisplay: String) -> String {
        var parts: [String] = []
        if modifiers.contains(.command) { parts.append("⌘") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.control) { parts.append("⌃") }
        parts.append(keyDisplay)
        return parts.joined(separator: " + ")
    }

    private func keyDisplay(for event: NSEvent) -> String {
        if let mapped = HotKeyBinding.keyCodeToDisplayString(Int(event.keyCode)), mapped != "?" {
            return mapped
        }

        if let characters = event.charactersIgnoringModifiers?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !characters.isEmpty {
            return characters.uppercased()
        }

        return fallbackKeyDisplay(for: Int(event.keyCode))
    }

    private func fallbackKeyDisplay(for keyCode: Int) -> String {
        switch keyCode {
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Space: return "Space"
        case kVK_Delete: return "Delete"
        case kVK_ForwardDelete: return "Forward Delete"
        case kVK_Escape: return "Escape"
        case kVK_LeftArrow: return "Left Arrow"
        case kVK_RightArrow: return "Right Arrow"
        case kVK_UpArrow: return "Up Arrow"
        case kVK_DownArrow: return "Down Arrow"
        case kVK_PageUp: return "Page Up"
        case kVK_PageDown: return "Page Down"
        case kVK_Home: return "Home"
        case kVK_End: return "End"
        case kVK_Help: return "Help"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default: return "Key \(keyCode)"
        }
    }

    private func normalizedToken(from value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .uppercased()
    }

    private func appendEvent(_ event: KeyboardOverlayEvent) {
        if let last = events.last,
           last.label == event.label,
           abs(last.timeOffset - event.timeOffset) < 0.03 {
            return
        }
        events.append(event)
    }
}

private struct FilteredKeyboardOverlayEvent: Sendable {
    let timeOffset: TimeInterval
    let label: String
    let duration: TimeInterval
}

private let keyboardChordChainGap: TimeInterval = 0.6

enum KeyboardOverlayProcessor {
    static func overlayOnVideo(
        sourceURL: URL,
        region: CaptureRegion,
        events: [KeyboardOverlayEvent],
        outputURL: URL,
        style: KeyboardOverlayStyle,
        displayMode: KeyboardOverlayDisplayMode,
        customKeys: Set<String>,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> URL {
        _ = region
        onProgress?(0.1)
        let filteredEvents = filterEvents(events, displayMode: displayMode, customKeys: customKeys, baseDuration: style.duration)
        guard !filteredEvents.isEmpty else {
            onProgress?(1.0)
            return sourceURL
        }

        let asset = AVURLAsset(url: sourceURL)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            onProgress?(1.0)
            return sourceURL
        }
        let assetDuration = try await asset.load(.duration)
        let videoPreferredTransform = try await videoTrack.load(.preferredTransform)
        onProgress?(0.25)

        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return sourceURL
        }

        try compositionVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: assetDuration), of: videoTrack, at: .zero)
        compositionVideoTrack.preferredTransform = videoPreferredTransform

        for audioTrack in try await asset.loadTracks(withMediaType: .audio) {
            if let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                try compositionAudioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: assetDuration), of: audioTrack, at: .zero)
            }
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let transformedSize = naturalSize.applying(videoPreferredTransform)
        let renderSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
        let sourceTimescale = max(30, Int32(nominalFrameRate.rounded(.up)))
        videoComposition.frameDuration = CMTime(value: 1, timescale: sourceTimescale)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: assetDuration)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        layerInstruction.setTransform(videoPreferredTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.isGeometryFlipped = true

        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.addSublayer(videoLayer)

        onProgress?(0.55)
        for event in filteredEvents where event.timeOffset <= assetDuration.seconds {
            let eventLayer = makeVideoEventLayer(label: event.label, renderSize: renderSize, style: style)
            let animation = makeVideoAnimation(style: style, duration: event.duration)
            animation.beginTime = AVCoreAnimationBeginTimeAtZero + event.timeOffset
            eventLayer.add(animation, forKey: "keyboard-overlay-anim")
            parentLayer.addSublayer(eventLayer)
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

        onProgress?(0.8)
        try await exportSession.export(to: outputURL, as: .mp4)

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: sourceURL)
        }
        onProgress?(1.0)
        return outputURL
    }

    static func overlayOnGif(
        gifData: GifCaptureData,
        region: CaptureRegion,
        events: [KeyboardOverlayEvent],
        style: KeyboardOverlayStyle,
        displayMode: KeyboardOverlayDisplayMode,
        customKeys: Set<String>
    ) -> GifCaptureData {
        _ = region
        let filteredEvents = filterEvents(events, displayMode: displayMode, customKeys: customKeys, baseDuration: style.duration)
        guard !filteredEvents.isEmpty else {
            return gifData
        }

        var processedFrames: [CGImage] = []
        processedFrames.reserveCapacity(gifData.frames.count)

        for (index, frame) in gifData.frames.enumerated() {
            let frameTime = Double(index) * gifData.frameDelay
            processedFrames.append(drawKeyboardOverlay(on: frame, at: frameTime, events: filteredEvents, style: style))
        }

        return GifCaptureData(frames: processedFrames, frameDelay: gifData.frameDelay, maxWidth: gifData.maxWidth)
    }

    private static func filterEvents(
        _ events: [KeyboardOverlayEvent],
        displayMode: KeyboardOverlayDisplayMode,
        customKeys: Set<String>,
        baseDuration: TimeInterval
    ) -> [FilteredKeyboardOverlayEvent] {
        let normalizedCustom = Set(customKeys.map { $0.uppercased() })
        let passes: [KeyboardOverlayEvent] = events.compactMap { event in
            switch displayMode {
            case .allKeys:
                return event
            case .nonModifierKeys:
                return event.isModifierOnly ? nil : event
            case .customSubset:
                guard !normalizedCustom.isEmpty, normalizedCustom.contains(event.keyToken.uppercased()) else {
                    return nil
                }
                return event
            }
        }
        return coalesceChords(passes, baseDuration: baseDuration)
    }

    private static func coalesceChords(
        _ events: [KeyboardOverlayEvent],
        baseDuration: TimeInterval
    ) -> [FilteredKeyboardOverlayEvent] {
        guard !events.isEmpty else { return [] }

        var output: [FilteredKeyboardOverlayEvent] = []
        var current: [KeyboardOverlayEvent] = []

        func flush() {
            guard let first = current.first, let last = current.last else { return }
            let label: String
            if let lastKeyDown = current.last(where: { !$0.isModifierOnly }) {
                // The key-down label already contains its modifier glyphs.
                label = lastKeyDown.label
            } else {
                // Pure modifier-only chord (held without a terminal key).
                label = current.map(\.label).joined(separator: " + ")
            }
            let span = max(0, last.timeOffset - first.timeOffset)
            output.append(
                FilteredKeyboardOverlayEvent(
                    timeOffset: first.timeOffset,
                    label: label,
                    duration: span + baseDuration
                )
            )
            current.removeAll(keepingCapacity: true)
        }

        for event in events {
            guard let prev = current.last else {
                current.append(event)
                continue
            }
            let withinGap = (event.timeOffset - prev.timeOffset) <= keyboardChordChainGap
            // Two consecutive non-modifier keys split into separate chords so typing
            // sequences (e.g. "abc") show as discrete bubbles instead of one merged label.
            let bothTerminal = !event.isModifierOnly && current.contains(where: { !$0.isModifierOnly })
            if withinGap && !bothTerminal {
                current.append(event)
            } else {
                flush()
                current.append(event)
            }
        }
        flush()
        return output
    }

    private static func makeVideoEventLayer(label: String, renderSize: CGSize, style: KeyboardOverlayStyle) -> CALayer {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let bubble = renderKeyboardBubbleImage(label: label, style: style, alpha: 1.0, scale: scale)

        let container = CALayer()
        container.frame = positionedRectFlipped(itemSize: bubble.pointSize, canvasSize: renderSize, position: style.position)
        container.contentsGravity = .resizeAspect
        container.contents = bubble.image
        container.contentsScale = scale
        container.opacity = 0
        return container
    }

    private struct KeyboardBubbleImage {
        let image: CGImage
        let pointSize: CGSize
    }

    private static func renderKeyboardBubbleImage(
        label: String,
        style: KeyboardOverlayStyle,
        alpha: CGFloat,
        scale: CGFloat
    ) -> KeyboardBubbleImage {
        let fontSize = max(12, style.fontSize)
        let paddingX = max(12, fontSize * 0.55)
        let paddingY = max(6, fontSize * 0.35)
        let textColor = contrastingTextColor(for: style.color).withAlphaComponent(alpha)
        let attributed = keyboardOverlayAttributedString(label: label, fontSize: fontSize, color: textColor)
        let textSize = attributed.size()

        let bubblePointSize = CGSize(
            width: ceil(textSize.width + (paddingX * 2)),
            height: ceil(textSize.height + (paddingY * 2))
        )
        let pixelWidth = max(1, Int((bubblePointSize.width * scale).rounded(.up)))
        let pixelHeight = max(1, Int((bubblePointSize.height * scale).rounded(.up)))

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return KeyboardBubbleImage(image: blankImage(), pointSize: bubblePointSize)
        }

        context.scaleBy(x: scale, y: scale)

        let bubbleRect = CGRect(origin: .zero, size: bubblePointSize)
        let cornerRadius: CGFloat
        switch style.shapeStyle {
        case .capsule: cornerRadius = bubbleRect.height / 2
        case .minimal: cornerRadius = 6
        case .roundedRect: cornerRadius = 10
        }

        let bgAlpha = (style.shapeStyle == .minimal ? 0.6 : 0.82) * alpha
        context.setFillColor(style.color.withAlphaComponent(bgAlpha).cgColor)
        context.addPath(CGPath(roundedRect: bubbleRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
        context.fillPath()

        // Draw the attributed string via AppKit so font metrics & color match what was measured.
        let textOrigin = CGPoint(
            x: paddingX + max(0, (bubblePointSize.width - (paddingX * 2) - textSize.width) / 2),
            y: paddingY
        )
        let textRect = CGRect(origin: textOrigin, size: textSize)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        attributed.draw(in: textRect)
        NSGraphicsContext.restoreGraphicsState()

        let cgImage = context.makeImage() ?? blankImage()
        return KeyboardBubbleImage(image: cgImage, pointSize: bubblePointSize)
    }

    private static func blankImage() -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )!
        return ctx.makeImage()!
    }

    private static func makeVideoAnimation(style: KeyboardOverlayStyle, duration: TimeInterval) -> CAAnimationGroup {
        let group = CAAnimationGroup()
        group.duration = duration
        group.isRemovedOnCompletion = false
        group.fillMode = .both

        let fadeIn = min(0.15, max(0.05, 0.12 / duration))
        let fadeOutStart = 1 - min(0.35, max(0.1, 0.3 / duration))
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0, 1, 1, 0]
        opacity.keyTimes = [0, NSNumber(value: fadeIn), NSNumber(value: fadeOutStart), 1]

        let transform = CAKeyframeAnimation(keyPath: "transform")
        switch style.animationStyle {
        case .fade:
            transform.values = [CATransform3DIdentity, CATransform3DIdentity, CATransform3DIdentity]
            transform.keyTimes = [0, 0.5, 1]
        case .slide:
            transform.values = [
                CATransform3DMakeTranslation(0, 10, 0),
                CATransform3DIdentity,
                CATransform3DMakeTranslation(0, -6, 0)
            ]
            transform.keyTimes = [0, 0.3, 1]
        case .pop:
            transform.values = [
                CATransform3DMakeScale(0.85, 0.85, 1),
                CATransform3DMakeScale(1.03, 1.03, 1),
                CATransform3DIdentity
            ]
            transform.keyTimes = [0, 0.25, 1]
        }

        group.animations = [opacity, transform]
        return group
    }

    private static func drawKeyboardOverlay(
        on image: CGImage,
        at frameTime: TimeInterval,
        events: [FilteredKeyboardOverlayEvent],
        style: KeyboardOverlayStyle
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

        guard let event = events.last(where: { frameTime >= $0.timeOffset && frameTime <= ($0.timeOffset + $0.duration) }) else {
            return context.makeImage() ?? image
        }

        let elapsed = frameTime - event.timeOffset
        let duration = max(0.0001, event.duration)
        let progress = max(0, min(1, elapsed / duration))
        let fadeIn = min(0.15, max(0.05, 0.12 / duration))
        let fadeOutStart = 1 - min(0.35, max(0.1, 0.3 / duration))
        let alpha: CGFloat
        if progress < fadeIn {
            alpha = CGFloat(progress / fadeIn)
        } else if progress > fadeOutStart {
            alpha = CGFloat(max(0, (1 - progress) / max(0.0001, 1 - fadeOutStart)))
        } else {
            alpha = 1
        }

        let bubble = renderKeyboardBubbleImage(label: event.label, style: style, alpha: alpha, scale: 1.0)
        var drawRect = positionedRect(
            itemSize: bubble.pointSize,
            canvasSize: CGSize(width: image.width, height: image.height),
            position: style.position
        )

        if style.animationStyle == .slide {
            drawRect.origin.y += (1 - progress) * 8
        }

        context.draw(bubble.image, in: drawRect)
        return context.makeImage() ?? image
    }

    private static func keyboardOverlayAttributedString(label: String, fontSize: CGFloat, color: NSColor) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        return NSAttributedString(
            string: label,
            attributes: [
                .font: font,
                .foregroundColor: color
            ]
        )
    }

    private static func positionedRect(itemSize: CGSize, canvasSize: CGSize, position: KeyboardOverlayPosition) -> CGRect {
        let marginX: CGFloat = max(16, itemSize.height * 0.6)
        let marginY: CGFloat = max(16, itemSize.height * 0.8)

        let x: CGFloat
        switch position {
        case .topLeading, .bottomLeading:
            x = marginX
        case .topCenter, .bottomCenter:
            x = max(marginX, (canvasSize.width - itemSize.width) / 2)
        case .topTrailing, .bottomTrailing:
            x = max(marginX, canvasSize.width - itemSize.width - marginX)
        }

        let y: CGFloat
        switch position {
        case .topLeading, .topCenter, .topTrailing:
            y = max(marginY, canvasSize.height - itemSize.height - marginY)
        case .bottomLeading, .bottomCenter, .bottomTrailing:
            y = marginY
        }

        return CGRect(origin: CGPoint(x: x, y: y), size: itemSize)
    }

    private static func positionedRectFlipped(itemSize: CGSize, canvasSize: CGSize, position: KeyboardOverlayPosition) -> CGRect {
        var rect = positionedRect(itemSize: itemSize, canvasSize: canvasSize, position: position)
        switch position {
        case .topLeading, .topCenter, .topTrailing:
            rect.origin.y = max(16, itemSize.height * 0.8)
        case .bottomLeading, .bottomCenter, .bottomTrailing:
            rect.origin.y = max(16, canvasSize.height - itemSize.height - max(16, itemSize.height * 0.8))
        }
        return rect
    }

    private static func contrastingTextColor(for color: NSColor) -> NSColor {
        guard let rgb = color.usingColorSpace(.sRGB) else { return .white }
        let luminance = (0.2126 * rgb.redComponent) + (0.7152 * rgb.greenComponent) + (0.0722 * rgb.blueComponent)
        return luminance > 0.6 ? .black : .white
    }
}
