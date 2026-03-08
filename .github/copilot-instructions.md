# TinyClips — Project Guidelines

TinyClips is a macOS menu bar app for screen capture (screenshots, video, GIF). It targets **macOS 15.0+**, uses **Swift 5** with an Xcode project (no Package.swift), and has **Sparkle** as its only dependency (via SPM) for direct distribution builds.

The project supports two app variants from one codebase:
- **Direct distribution target:** `TinyClips` (non-sandboxed, Sparkle-enabled)
- **Mac App Store target:** `TinyClipsMAS` (sandboxed, no Sparkle linkage, `APPSTORE` compilation condition)

## Architecture

- **Menu bar app** using SwiftUI `MenuBarExtra` + `Settings` scene — no Dock icon (`LSUIElement = true`)
- **Mixed SwiftUI + AppKit**: SwiftUI for menu bar content, settings, and inline UI; AppKit `NSWindow`/`NSPanel` subclasses for all floating windows (stop panel, trimmer, editor). AppKit windows host SwiftUI views via `NSHostingView`.
- **`CaptureManager`** in `TinyClipsApp.swift` is the central coordinator owning recorders, writers, and editor windows.
- **Singleton services**: `CaptureSettings.shared`, `SaveService.shared`, `PermissionManager.shared`, `SparkleController.shared`.
- **Direct target is not sandboxed** — hardened runtime is enabled.
- **App Store target is sandboxed** with separate entitlements and Info.plist.

## Code Style

- Use `ObservableObject` / `@Published` / `@StateObject` — **not** `@Observable` (Observation framework).
- Use `@AppStorage` for all user preferences (see `TinyClips/Models/CaptureSettings.swift`).
- Mark all UI-facing classes with `@MainActor`. Use `@unchecked Sendable` + dispatch queues for off-main-thread capture classes.
- Use `// MARK: -` comments for section organization within files.
- Keep SwiftUI views inside window files as `private struct`.
- Use `popover(item:)` over `popover(isPresented:)` for data-dependent popovers.
- Guard Sparkle imports with `#if canImport(Sparkle)`.
- Use `#if APPSTORE` for MAS-specific UI/behavior differences and keep direct target behavior unchanged by default.

## Build and Test

```bash
# Build (CI, no signing)
xcodebuild build -project TinyClips.xcodeproj -scheme TinyClips -configuration Debug \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# Build Mac App Store variant (CI, no signing)
xcodebuild build -project TinyClips.xcodeproj -scheme TinyClipsMAS -configuration Debug \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# Local development
open TinyClips.xcodeproj  # then ⌘R in Xcode
```

No test target exists. Adding Sparkle dependency requires following `docs/sparkle-setup.md`.
App Store variant setup details are in `docs/app-store-variant-setup.md`.

## Project Conventions

### Window Pattern
AppKit `NSWindow`/`NSPanel` subclass with `convenience init(..., onComplete: @escaping (URL?) -> Void)`, hosting SwiftUI via `NSHostingView`. Always set `isReleasedWhenClosed = false`. Use a `didComplete` bool guard to prevent double-completion. `nil` from `onComplete` means cancelled. See `TinyClips/Views/VideoTrimmerWindow.swift` for reference.

### Floating Panel Recipe
Panels (`StopRecordingPanel`, `StartRecordingPanel`, `CountdownWindow`) use: `styleMask: [.borderless, .nonactivatingPanel]`, `level = .floating`, `backgroundColor = .clear`, `isOpaque = false`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`.

### Window Lifecycle
`CaptureManager` holds a strong reference to windows and defers `nil`'ing via `DispatchQueue.main.async` to avoid deallocating mid-callback. Same pattern for `makeKeyAndOrderFront` to escape menu tracking run loops.

### Capture Flows
1. **Screenshot:** permission → region select → `ScreenshotCapture.capture()` → optional editor → save
2. **Video:** permission → region select → `StartRecordingPanel` → optional countdown → `VideoRecorder.start()` → `StopRecordingPanel` → stop → optional trimmer → save
3. **GIF:** permission → region select → optional countdown → `GifWriter.start()` → `StopRecordingPanel` → stop → optional trimmer → save

Editor/trimmer windows are shown **after** all recording resources are released to avoid file contention.

### Async/Await Bridging
- Use `withCheckedContinuation` / `withCheckedThrowingContinuation` to bridge callback APIs to async (e.g., region selector, `AVAssetWriter.finishWriting`).
- Recording start/stop methods are `async throws`.
- No `@Sendable` closures or actors — use `DispatchQueue` for thread safety on capture classes.

### Region Selector
- Static async entry: `await RegionSelector.selectRegion()` returns `CaptureRegion?`.
- Creates one fullscreen `NSWindow` overlay per `NSScreen.screens` at `.screenSaver` level. Uses raw `NSView` subclass (not SwiftUI) with crosshair cursor.
- Minimum selection: 10×10 points. Coordinate chain: view → window → screen → display-local (Y-flipped).
- `CaptureRegion` is a `Sendable` struct with `makeStreamConfig()` (sync) and `makeFilter()` (async, excludes own app windows).

### Error Handling
Single `CaptureError` enum conforming to `LocalizedError`. Surface errors via `SaveService.shared.showError()` which presents `NSAlert`.

### File Naming
Output: `TinyClips yyyy-MM-dd 'at' HH.mm.ss.{ext}`. Trimmed video gets ` (trimmed)` suffix, original is deleted. Cancelled editor operations clean up via `try? FileManager.default.removeItem(at:)`.

### Keyboard Shortcuts
Screenshot `⌘⇧5`, Video `⌘⇧6`, GIF `⌘⇧7`, Stop `⌘.`, Settings `⌘,`, Quit `⌘Q`. Dialogs use `.keyboardShortcut(.defaultAction)` / `.keyboardShortcut(.cancelAction)`.

### Accessibility (VoiceOver + Keyboard)
- Treat accessibility as a release gate for capture flows, settings, onboarding, editors/trimmers, and Clips Manager.
- Add explicit `.accessibilityLabel`, `.accessibilityHint`, and `.accessibilityValue` for icon-only buttons, custom controls, toggles, timers, and stateful UI.
- Keep pointer-heavy custom controls keyboard-accessible (for example: default/cancel shortcuts, `Esc` cancel paths, numeric display selection, and Stepper-based trim adjustments).
- Prefer semantic structure in SwiftUI (`.accessibilityAddTraits(.isHeader)`, grouped elements, clear control names) over relying only on `.help(...)` tooltips.
- Validate accessibility changes on both schemes (`TinyClips` and `TinyClipsMAS`) and manually verify VoiceOver + keyboard-only navigation on critical paths.

### Notifications & Clipboard
- Post-save notifications via `UserNotifications` framework (`UNMutableNotificationContent`), not `NSUserNotification`.
- All inter-component communication uses **closures/callbacks**, no `NotificationCenter` posting.
- Clipboard: screenshots as `NSImage`, video/GIF as `NSURL`.

### Audio Recording
- System audio via `SCStream` (`capturesAudio = true`, 48kHz stereo AAC 128kbps).
- Microphone via separate `AVAudioEngine` tap, converted to 48kHz mono AAC. Uses host time for clock alignment with SCStream.
- Three `AVAssetWriterInput` instances: video, system audio, mic audio.

### Settings View
- `SettingsTab` enum (`CaseIterable`, `rawValue` = display title, `icon` computed property for SF Symbol).
- `Form` with `.formStyle(.grouped)`. Each tab is a `@ViewBuilder private var`.
- Fixed frame: `.frame(width: 420, height: 340)`.
- For MAS (`APPSTORE`): keep save location UI minimal and sandbox-safe (default Pictures/Movies behavior plus user-selected folder bookmark path display).

## Security

- Direct target entitlements: audio input, disabled library validation (for Sparkle), **not sandboxed**.
- MAS target entitlements: sandbox enabled, Pictures/Movies read-write, audio input, no Sparkle-related library validation bypass.
- Screen recording: dual-check — `CGPreflightScreenCaptureAccess()` first, then `SCShareableContent` query as fallback for macOS 15+ false negatives.
- Microphone: `NSMicrophoneUsageDescription` in Info.plist, requested at recording time via `AVCaptureDevice.requestAccess(for: .audio)`.
