import AppKit
import ScreenCaptureKit

// MARK: - Window Selector

@MainActor
class WindowSelector {
    private static var activeSelector: WindowSelectorController?

    static func selectWindow() async -> SCWindow? {
        let windows: [SCWindow]
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            windows = content.windows.filter { w in
                w.frame.width >= 50 && w.frame.height >= 50
                    && w.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier
                    && w.isOnScreen
            }
        } catch {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let controller = WindowSelectorController(windows: windows) { window in
                Self.activeSelector = nil
                continuation.resume(returning: window)
            }
            Self.activeSelector = controller
            controller.show()
        }
    }
}

// MARK: - Controller

@MainActor
private class WindowSelectorController {
    private var overlayWindows: [(window: NSWindow, screen: NSScreen)] = []
    private let scWindows: [SCWindow]
    private let completion: (SCWindow?) -> Void
    private var hoveredWindow: SCWindow?
    private let primaryScreenHeight: CGFloat

    init(windows: [SCWindow], completion: @escaping (SCWindow?) -> Void) {
        self.scWindows = windows
        self.completion = completion
        self.primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 0
    }

    func show() {
        for screen in NSScreen.screens {
            let window = WindowOverlayWindow(
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

            let view = WindowSelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.onMouseMoved = { [weak self] in
                self?.updateHoveredWindow(at: NSEvent.mouseLocation)
            }
            view.onMouseDown = { [weak self] in
                self?.selectHoveredWindow()
            }
            view.onCancel = { [weak self] in
                self?.finish(with: nil)
            }
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)
            overlayWindows.append((window: window, screen: screen))
        }

        // Show highlight for window under cursor at launch
        updateHoveredWindow(at: NSEvent.mouseLocation)
    }

    private func updateHoveredWindow(at globalPoint: NSPoint) {
        // Convert AppKit (Y-up) to SC coordinates (Y-down from top of primary screen)
        let scPoint = CGPoint(x: globalPoint.x, y: primaryScreenHeight - globalPoint.y)

        // Find topmost window (first in the array = frontmost) containing the point
        let newHovered = scWindows.first { w in w.frame.contains(scPoint) }

        if newHovered?.windowID != hoveredWindow?.windowID {
            hoveredWindow = newHovered
            updateHighlights()
        }
    }

    private func updateHighlights() {
        for (overlayWindow, screen) in overlayWindows {
            guard let view = overlayWindow.contentView as? WindowSelectionView else { continue }
            if let hovered = hoveredWindow {
                let appKitFrame = scFrameToAppKit(hovered.frame)
                let screenFrame = screen.frame
                let intersection = screenFrame.intersection(appKitFrame)
                if intersection.isNull || intersection.isEmpty {
                    view.highlightFrame = nil
                } else {
                    view.highlightFrame = CGRect(
                        x: intersection.origin.x - screenFrame.origin.x,
                        y: intersection.origin.y - screenFrame.origin.y,
                        width: intersection.width,
                        height: intersection.height
                    )
                }
            } else {
                view.highlightFrame = nil
            }
            view.needsDisplay = true
        }
    }

    private func selectHoveredWindow() {
        finish(with: hoveredWindow)
    }

    private func finish(with window: SCWindow?) {
        for (w, _) in overlayWindows {
            w.orderOut(nil)
        }
        overlayWindows.removeAll()
        completion(window)
    }

    /// Converts a rect from SC coordinates (origin top-left, Y-down) to AppKit coordinates (origin bottom-left, Y-up).
    private func scFrameToAppKit(_ scFrame: CGRect) -> CGRect {
        CGRect(
            x: scFrame.origin.x,
            y: primaryScreenHeight - scFrame.maxY,
            width: scFrame.width,
            height: scFrame.height
        )
    }
}

// MARK: - Selection View

private class WindowSelectionView: NSView {
    var onMouseMoved: (() -> Void)?
    var onMouseDown: (() -> Void)?
    var onCancel: (() -> Void)?

    var highlightFrame: NSRect? {
        didSet { needsDisplay = true }
    }

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.3).setFill()
        bounds.fill()

        if let frame = highlightFrame {
            // Clear the selected window area
            NSColor.clear.setFill()
            frame.fill(using: .copy)

            // Draw white border
            NSColor.white.setStroke()
            let path = NSBezierPath(roundedRect: frame.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4)
            path.lineWidth = 2.0
            path.stroke()
        }
    }

    override func mouseMoved(with event: NSEvent) {
        onMouseMoved?()
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onCancel?()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways],
            owner: self,
            userInfo: nil
        ))
    }
}

// MARK: - Overlay Window

private class WindowOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}
