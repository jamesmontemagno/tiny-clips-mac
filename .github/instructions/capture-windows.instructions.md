---
description: "Use when editing capture-time AppKit windows or floating panels: StopRecordingPanel, StartRecordingPanel, CapturePickerPanel, CountdownWindow, ScreenPickerWindow, RegionIndicatorPanel, VideoTrimmerWindow, GifTrimmerWindow, ScreenshotEditorWindow, OnboardingWizardWindow, GuideWindow."
applyTo: "TinyClips/Views/*Panel.swift, TinyClips/Views/*Window.swift"
---

# Capture-Time Window & Panel Conventions

## Floating Panel Recipe

Floating capture panels (`NSPanel` subclass) use this setup in `init`:

```swift
self.init(
    contentRect: NSRect(x: 0, y: 0, width: ..., height: ...),
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false
)
self.isReleasedWhenClosed = false
self.level = .floating
self.isOpaque = false
self.backgroundColor = .clear
self.hasShadow = true
self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
self.isMovableByWindowBackground = true
```

Editor/trimmer windows (`NSWindow` subclass) use titled style instead:
`styleMask: [.titled, .closable, .miniaturizable, .resizable]`

## Callback Pattern with Double-Fire Guard

Every callback-driven window must prevent double invocations:

```swift
class SomeWindow: NSWindow, NSWindowDelegate {
    private var onComplete: ((ResultType?) -> Void)?
    private var didComplete = false

    private func completeWith(_ result: ResultType?) {
        guard !didComplete, let callback = onComplete else { return }
        didComplete = true
        onComplete = nil       // nil BEFORE calling to prevent re-entrancy
        callback(result)
        orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        completeWith(nil)      // nil payload = cancelled
        return true
    }
}
```

Rules:
- Set `didComplete = true` and `onComplete = nil` **before** invoking the callback.
- `nil` result payload always means the user cancelled.
- Set `isReleasedWhenClosed = false` — `CaptureManager` owns the lifecycle.
- Use `[weak self]` in all closures passed to hosted SwiftUI views.

## SwiftUI Integration

Host SwiftUI views via `NSHostingView`:

```swift
let hostingView = NSHostingView(rootView: SomeView(
    onAction: { [weak self] value in
        self?.completeWith(value)
    }
))
self.contentView = hostingView
```

Keep SwiftUI views as `private struct` inside the window file.

## Keyboard Interactivity (Picker Panels)

Panels that need keyboard input must:
- Override `var canBecomeKey: Bool { true }`
- Call `NSApp.activate()` after `makeKeyAndOrderFront`
- Install local + global event monitors (`NSEvent.addLocalMonitorForEvents` / `addGlobalMonitorForEvents`)
- Remove monitors in the completion/cancel path

## Lifecycle

- `CaptureManager` holds strong refs to capture-time windows.
- Defer `nil` releases with `DispatchQueue.main.async` — avoids deallocation mid-callback.
- Persist floating panel positions on dismiss and restore on reopen.
- Editor/trimmer windows open **after** recording resources are fully released.
