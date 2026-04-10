import AppKit
import CoreVideo
import CoreText
import CoreGraphics

// MARK: - KeyboardOverlayMode

enum KeyboardOverlayMode: String, CaseIterable {
    case all = "all"
    case nonModifiers = "nonModifiers"
    case modifiersOnly = "modifiersOnly"

    var label: String {
        switch self {
        case .all: return "All Keys"
        case .nonModifiers: return "Non-Modifiers Only"
        case .modifiersOnly: return "Modifiers Only"
        }
    }
}

// MARK: - KeyboardOverlayPosition

enum KeyboardOverlayPosition: String, CaseIterable {
    case bottomCenter = "bottomCenter"
    case bottomLeft = "bottomLeft"
    case bottomRight = "bottomRight"
    case topLeft = "topLeft"
    case topRight = "topRight"

    var label: String {
        switch self {
        case .bottomCenter: return "Bottom Center"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        }
    }
}

// MARK: - KeyPressRecord

struct KeyPressRecord {
    let text: String
    let timestamp: TimeInterval
}

// MARK: - KeyboardOverlayRenderer

/// Monitors global key events and composites a key-press history badge row
/// onto captured frames (CVPixelBuffer for video, CGImage for GIF).
///
/// Thread-safety strategy:
/// - `eventMonitor`/`flagsMonitor` are registered and removed exclusively on the main thread
///   (via DispatchQueue.main.async) since NSEvent monitors must be managed on the main thread.
/// - `activeKeys`, `lastModifierText`, and `mode` are protected by the serial `queue`.
///   Event handlers are called on the main thread and dispatch to `queue` for mutations.
/// - `renderOnto` is called from background queues (writingQueue / processingQueue) and
///   reads state via `queue.sync { ... }`, which is safe since those queues differ from `queue`.
class KeyboardOverlayRenderer: @unchecked Sendable {
    // MARK: - Configuration

    private let maxKeys = 5
    private let displayDuration: TimeInterval = 1.8
    private let solidDuration: TimeInterval = 1.2
    private let fadeDuration: TimeInterval = 0.6

    // MARK: - State (protected by `queue`)

    private var activeKeys: [KeyPressRecord] = []
    private var lastModifierText: String = ""

    // MARK: - Private

    private var eventMonitor: Any?
    private var flagsMonitor: Any?
    private var mode: KeyboardOverlayMode = .all
    private let queue = DispatchQueue(label: "com.tinyclips.keyboard-overlay")

    // MARK: - Monitoring

    /// Start recording key events. Safe to call from any thread.
    func startMonitoring(mode: KeyboardOverlayMode) {
        self.mode = mode
        stopMonitoring()

        // Global monitors so we receive events even when non-activating panels are front.
        // NSEvent monitor registration must happen on the main thread.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleKeyDown(event)
            }
            self.flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.handleFlagsChanged(event)
            }
        }
    }

    /// Stop recording key events and clear history. Safe to call from any thread.
    func stopMonitoring() {
        // NSEvent monitor removal is dispatched to main thread to pair correctly
        // with the async registration in startMonitoring.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let monitor = self.eventMonitor {
                NSEvent.removeMonitor(monitor)
                self.eventMonitor = nil
            }
            if let monitor = self.flagsMonitor {
                NSEvent.removeMonitor(monitor)
                self.flagsMonitor = nil
            }
        }
        queue.sync {
            activeKeys.removeAll()
            lastModifierText = ""
        }
    }

    // MARK: - Event Handlers (main thread)

    private func handleKeyDown(_ event: NSEvent) {
        guard mode != .modifiersOnly else { return }
        let text = keyText(from: event)
        guard !text.isEmpty else { return }
        queue.async { [weak self] in
            guard let self else { return }
            let record = KeyPressRecord(text: text, timestamp: CACurrentMediaTime())
            activeKeys.append(record)
            if activeKeys.count > maxKeys {
                activeKeys.removeFirst(activeKeys.count - maxKeys)
            }
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        guard mode != .nonModifiers else { return }
        let text = modifierText(from: event.modifierFlags)
        if text.isEmpty {
            queue.async { [weak self] in self?.lastModifierText = "" }
            return
        }
        queue.async { [weak self] in
            guard let self, text != lastModifierText else { return }
            lastModifierText = text
            let record = KeyPressRecord(text: text, timestamp: CACurrentMediaTime())
            activeKeys.append(record)
            if activeKeys.count > maxKeys {
                activeKeys.removeFirst(activeKeys.count - maxKeys)
            }
        }
    }

    // MARK: - Key Text Helpers

    private func keyText(from event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case 36: return "↩"   // Return
        case 51: return "⌫"   // Delete / Backspace
        case 53: return "⎋"   // Escape
        case 49: return "␣"   // Space
        case 48: return "⇥"   // Tab
        case 123: return "←"  // Left arrow
        case 124: return "→"  // Right arrow
        case 125: return "↓"  // Down arrow
        case 126: return "↑"  // Up arrow
        case 116: return "⇞"  // Page Up
        case 121: return "⇟"  // Page Down
        case 115: return "↖"  // Home
        case 119: return "↘"  // End
        default: break
        }

        var prefix = ""
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if mods.contains(.control) { prefix += "⌃" }
        if mods.contains(.option)  { prefix += "⌥" }
        if mods.contains(.shift)   { prefix += "⇧" }
        if mods.contains(.command) { prefix += "⌘" }

        let char = event.charactersIgnoringModifiers?.uppercased() ?? ""
        return prefix + char
    }

    private func modifierText(from flags: NSEvent.ModifierFlags) -> String {
        let relevant = flags.intersection([.command, .shift, .option, .control])
        var text = ""
        if relevant.contains(.control) { text += "⌃" }
        if relevant.contains(.option)  { text += "⌥" }
        if relevant.contains(.shift)   { text += "⇧" }
        if relevant.contains(.command) { text += "⌘" }
        return text
    }

    // MARK: - Active Keys Snapshot (must be called on `queue`)

    private func currentKeys() -> [(text: String, alpha: Double)] {
        let now = CACurrentMediaTime()
        activeKeys = activeKeys.filter { now - $0.timestamp < displayDuration }
        return activeKeys.map { record in
            let age = now - record.timestamp
            let alpha: Double
            if age <= solidDuration {
                alpha = 1.0
            } else {
                alpha = max(0, 1.0 - (age - solidDuration) / fadeDuration)
            }
            return (record.text, alpha)
        }
    }

    // MARK: - CVPixelBuffer Compositing (in-place, for video)

    /// Composites the key overlay directly onto a CVPixelBuffer (kCVPixelFormatType_32BGRA).
    func renderOnto(pixelBuffer: CVPixelBuffer, scaleFactor: Double, position: KeyboardOverlayPosition) {
        let keys = queue.sync { currentKeys() }
        guard !keys.isEmpty else { return }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }

        drawOverlay(keys: keys, in: context, width: width, height: height, scaleFactor: scaleFactor, position: position)
    }

    // MARK: - CGImage Compositing (new context, for GIF)

    /// Returns a new CGImage with the key overlay composited on top, or nil if no keys are visible.
    func renderOnto(image: CGImage, scaleFactor: Double, position: KeyboardOverlayPosition) -> CGImage? {
        let keys = queue.sync { currentKeys() }
        guard !keys.isEmpty else { return nil }

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
        ) else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        drawOverlay(keys: keys, in: context, width: width, height: height, scaleFactor: scaleFactor, position: position)
        return context.makeImage()
    }

    // MARK: - Core Drawing

    private func drawOverlay(
        keys: [(text: String, alpha: Double)],
        in context: CGContext,
        width: Int,
        height: Int,
        scaleFactor: Double,
        position: KeyboardOverlayPosition
    ) {
        let scale = max(1.0, scaleFactor)
        let fontSize = 14.0 * scale
        let hPad = 10.0 * scale
        let vPad = 6.0 * scale
        let cornerRadius = 8.0 * scale
        let spacing = 6.0 * scale
        let margin = 16.0 * scale

        let font = CTFontCreateWithName(".AppleSystemUIFont" as CFString, fontSize, nil)

        // Measure each badge
        let badges: [(text: String, size: CGSize, alpha: Double)] = keys.map { key in
            let attrStr = attributedString(key.text, font: font, color: CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            let line = CTLineCreateWithAttributedString(attrStr)
            let bounds = CTLineGetBoundsWithOptions(line, [])
            let w = ceil(bounds.width) + hPad * 2
            let h = ceil(bounds.height) + vPad * 2
            return (key.text, CGSize(width: w, height: h), key.alpha)
        }

        let totalWidth = badges.reduce(0.0) { $0 + $1.size.width } + spacing * Double(badges.count - 1)
        let maxHeight = badges.map { $0.size.height }.max() ?? 0

        let origin = badgeRowOrigin(
            totalWidth: totalWidth,
            totalHeight: maxHeight,
            canvasWidth: Double(width),
            canvasHeight: Double(height),
            margin: margin,
            position: position
        )

        var x = origin.x
        for badge in badges {
            let rect = CGRect(x: x, y: origin.y, width: badge.size.width, height: badge.size.height)
            drawBadge(text: badge.text, in: rect, cornerRadius: cornerRadius, alpha: badge.alpha,
                      context: context, font: font, hPad: hPad, vPad: vPad)
            x += badge.size.width + spacing
        }
    }

    private func badgeRowOrigin(
        totalWidth: Double,
        totalHeight: Double,
        canvasWidth: Double,
        canvasHeight: Double,
        margin: Double,
        position: KeyboardOverlayPosition
    ) -> CGPoint {
        switch position {
        case .bottomCenter:
            return CGPoint(x: (canvasWidth - totalWidth) / 2, y: margin)
        case .bottomLeft:
            return CGPoint(x: margin, y: margin)
        case .bottomRight:
            return CGPoint(x: canvasWidth - totalWidth - margin, y: margin)
        case .topLeft:
            return CGPoint(x: margin, y: canvasHeight - totalHeight - margin)
        case .topRight:
            return CGPoint(x: canvasWidth - totalWidth - margin, y: canvasHeight - totalHeight - margin)
        }
    }

    private func drawBadge(
        text: String,
        in rect: CGRect,
        cornerRadius: Double,
        alpha: Double,
        context: CGContext,
        font: CTFont,
        hPad: Double,
        vPad: Double
    ) {
        context.saveGState()

        // Background pill
        let bgColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0.72 * alpha)
        context.setFillColor(bgColor)
        let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        context.addPath(path)
        context.fillPath()

        // Label
        let textColor = CGColor(red: 1, green: 1, blue: 1, alpha: alpha)
        let attrStr = attributedString(text, font: font, color: textColor)
        let line = CTLineCreateWithAttributedString(attrStr)
        let bounds = CTLineGetBoundsWithOptions(line, [])

        // Center text inside badge
        let textX = rect.minX + hPad - bounds.minX
        let textY = rect.minY + vPad - bounds.minY
        context.textPosition = CGPoint(x: textX, y: textY)
        CTLineDraw(line, context)

        context.restoreGState()
    }

    private func attributedString(_ text: String, font: CTFont, color: CGColor) -> CFAttributedString {
        let attrStr = CFAttributedStringCreateMutable(nil, 0)!
        CFAttributedStringReplaceString(attrStr, CFRangeMake(0, 0), text as CFString)
        let range = CFRangeMake(0, CFStringGetLength(text as CFString))
        CFAttributedStringSetAttribute(attrStr, range, kCTFontAttributeName, font)
        CFAttributedStringSetAttribute(attrStr, range, kCTForegroundColorAttributeName, color)
        return attrStr
    }
}
