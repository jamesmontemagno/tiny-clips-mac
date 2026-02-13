import AppKit

@MainActor
class RegionSelector {
    private static var activeSelector: RegionSelectorController?

    static func selectRegion() async -> CaptureRegion? {
        return await withCheckedContinuation { continuation in
            let selector = RegionSelectorController(completion: { region in
                Self.activeSelector = nil
                continuation.resume(returning: region)
            })
            Self.activeSelector = selector
            selector.show()
        }
    }
}

@MainActor
private class RegionSelectorController {
    private var windows: [NSWindow] = []
    private let completion: (CaptureRegion?) -> Void
    private var eventMonitor: Any?

    init(completion: @escaping (CaptureRegion?) -> Void) {
        self.completion = completion
    }

    func show() {
        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = false
            window.acceptsMouseMovedEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let view = RegionSelectionView(frame: screen.frame)
            view.onComplete = { [weak self] region in
                self?.finish(with: region)
            }
            view.onCancel = { [weak self] in
                self?.finish(with: nil)
            }
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.finish(with: nil)
                return nil
            }
            return event
        }

        NSApp.activate()
        windows.first?.makeKey()
    }

    private func finish(with region: CaptureRegion?) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        completion(region)
    }
}

private class RegionSelectionView: NSView {
    var onComplete: ((CaptureRegion) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.3).setFill()
        bounds.fill()

        if let start = startPoint, let current = currentPoint {
            let selectionRect = makeRect(from: start, to: current)

            // Clear the selection area
            NSColor.clear.setFill()
            selectionRect.fill(using: .copy)

            // Draw border
            NSColor.white.setStroke()
            let path = NSBezierPath(rect: selectionRect)
            path.lineWidth = 1.5
            path.stroke()

            // Draw dashed inner border
            NSColor.white.withAlphaComponent(0.5).setStroke()
            let dashedPath = NSBezierPath(rect: selectionRect.insetBy(dx: 1, dy: 1))
            dashedPath.lineWidth = 0.5
            dashedPath.setLineDash([4, 4], count: 2, phase: 0)
            dashedPath.stroke()

            // Draw dimensions label
            drawDimensionsLabel(for: selectionRect)
        }
    }

    private func drawDimensionsLabel(for rect: NSRect) {
        let width = Int(abs(rect.width))
        let height = Int(abs(rect.height))
        guard width > 0, height > 0 else { return }

        let text = "\(width) × \(height)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let labelRect = NSRect(
            x: rect.midX - size.width / 2 - 6,
            y: rect.maxY + 8,
            width: size.width + 12,
            height: size.height + 6
        )

        NSColor.black.withAlphaComponent(0.7).setFill()
        let pill = NSBezierPath(roundedRect: labelRect, xRadius: 4, yRadius: 4)
        pill.fill()

        let textPoint = NSPoint(x: labelRect.minX + 6, y: labelRect.minY + 3)
        (text as NSString).draw(at: textPoint, withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = startPoint else { return }
        let end = convert(event.locationInWindow, from: nil)
        let selectionRect = makeRect(from: start, to: end)

        guard selectionRect.width >= 10, selectionRect.height >= 10 else {
            startPoint = nil
            currentPoint = nil
            needsDisplay = true
            return
        }

        guard let window = self.window, let screen = window.screen else { return }

        // Convert view coordinates → window coordinates → screen coordinates
        let windowRect = convert(selectionRect, to: nil)
        let screenRect = window.convertToScreen(windowRect)

        // Convert to display-local coordinates (origin at top-left, Y-down)
        let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID
        let localX = screenRect.minX - screen.frame.minX
        let localY = screen.frame.maxY - screenRect.maxY
        let sourceRect = CGRect(x: localX, y: localY, width: screenRect.width, height: screenRect.height)

        let region = CaptureRegion(
            sourceRect: sourceRect,
            displayID: displayID,
            scaleFactor: screen.backingScaleFactor
        )
        onComplete?(region)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        }
    }

    private func makeRect(from p1: NSPoint, to p2: NSPoint) -> NSRect {
        NSRect(
            x: min(p1.x, p2.x),
            y: min(p1.y, p2.y),
            width: abs(p2.x - p1.x),
            height: abs(p2.y - p1.y)
        )
    }
}
