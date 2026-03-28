# TinyClips — Project Guidelines

TinyClips is a macOS menu bar app for screen capture (screenshots, video, GIF). It targets **macOS 15.0+**, uses **Swift 5** with an Xcode project (no Package.swift), and has **Sparkle** as its only dependency (via SPM) for direct distribution builds.

The project supports two app variants from one codebase:
- **Direct distribution target:** `TinyClips` (non-sandboxed, Sparkle-enabled)
- **Mac App Store target:** `TinyClipsMAS` (sandboxed, no Sparkle linkage, `APPSTORE` compilation condition)

## Architecture

- **Menu bar app** using SwiftUI `MenuBarExtra` plus dedicated SwiftUI `Window` scenes for `clips-manager` and `settings-window` — no Dock icon by default (`LSUIElement = true`).
- **Mixed SwiftUI + AppKit**: SwiftUI for menu bar content, settings, and Clips Manager; AppKit `NSWindow`/`NSPanel` subclasses for capture-time and utility windows (picker panels, start/stop/countdown, screen picker, region indicator, editor/trimmer, onboarding, guide). AppKit windows host SwiftUI views via `NSHostingView`.
- **`CaptureManager`** in `TinyClipsApp.swift` is the central coordinator owning recorders, writers, and AppKit popup/window lifecycles used during capture flows.
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

### Agent Sandbox Guidance

- VS Code agent runs of `xcodebuild` may need `requestUnsandboxedExecution=true` because SwiftPM writes package caches and manifest diagnostics outside the workspace.
- If a sandboxed build fails with `Operation not permitted`, missing temp/cache directories, or SwiftPM manifest/diagnostics write errors such as `sparkle.dia`, rerun the same `xcodebuild` command unsandboxed.
- Apply the same unsandboxed retry rule to SwiftPM resolution commands that Xcode triggers for the Sparkle dependency.

No test target exists. Adding Sparkle dependency requires following `docs/sparkle-setup.md`.
App Store variant setup details are in `docs/app-store-variant-setup.md`.

## Project Conventions

### Window Pattern
Use SwiftUI `Window` scenes for long-lived app windows (`clips-manager`, `settings-window`) and AppKit subclasses for capture-time windows/panels.

For callback-driven AppKit windows/panels, keep a completion closure, guard with `didComplete`/`didClose` to prevent double-callbacks, set `isReleasedWhenClosed = false`, and nil out callbacks after firing.

For editor/trimmer/selection flows, `nil` completion payload means cancelled. See `TinyClips/Views/VideoTrimmerWindow.swift`, `TinyClips/Views/CapturePickerPanel.swift`, and `TinyClips/Views/ScreenPickerWindow.swift`.

### Floating Panel Recipe
Floating capture panels (`StopRecordingPanel`, `StartRecordingPanel`, `CountdownWindow`, `CapturePickerPanel`, `ScreenPickerWindow`, `RegionIndicatorPanel`) use: `styleMask: [.borderless, .nonactivatingPanel]`, `level = .floating`, `backgroundColor = .clear`, `isOpaque = false`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`.

Keyboard-interactive picker panels override `canBecomeKey`, call `NSApp.activate()`, and install/remove local+global key monitors (for shortcuts like `R`/`S`/`W`, number keys, and `Esc` cancel).

### Window Lifecycle
Open SwiftUI scene windows via `openWindow(id:)` from menu actions, then immediately activate and bring existing windows to front using identifier/title lookup (including a delayed second pass to escape menu tracking timing).

`CaptureManager` holds strong references to capture-time AppKit windows/panels and defers some `nil` releases with `DispatchQueue.main.async` to avoid deallocation mid-callback. Persist floating panel positions on dismiss and reuse them on reopen.

### Capture Flows
1. **Screenshot:** permission → `CapturePickerPanel` (region/screen/window + countdown) → optional `ScreenPickerWindow` for multi-display screen mode → optional `RegionIndicatorPanel` before countdown → capture → optional editor → save.
2. **Video:** permission → `CapturePickerPanel` (region/screen/window + countdown) → optional `RegionIndicatorPanel` for region mode → `StartRecordingPanel` → optional countdown → `VideoRecorder.start()` → `StopRecordingPanel` → stop → optional trimmer → save.
3. **GIF:** permission → `CapturePickerPanel` (region/screen/window + countdown) → optional `RegionIndicatorPanel` for region mode → `StartRecordingPanel` → optional countdown → `GifWriter.start()` → `StopRecordingPanel` → stop → optional trimmer → save.

Each capture type also has an independent "show capture picker" setting, defaulting to enabled. When disabled, that type skips the picker and goes straight to region selection; canceling region selection in that path cancels the request instead of reopening the picker.

Editor/trimmer windows are shown **after** all recording resources are released to avoid file contention.

### Popup Windows
- Onboarding uses `OnboardingWizardWindow` and is shown once on app startup when `hasCompletedOnboarding == false`.
- Guide uses a retained `GuideWindow`; if already open, bring it to front instead of creating a duplicate.
- Keep popup cleanup callback-driven and release strong refs on close/dismiss paths.

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
Screenshot `⌃⌥⌘5`, Video `⌃⌥⌘6`, GIF `⌃⌥⌘7`, Stop `⌘.`, Settings `⌘,`, Quit `⌘Q`. Picker shortcuts: Region `R`, Screen `S`, Window `W`, Cancel `Esc`. Dialogs use `.keyboardShortcut(.defaultAction)` / `.keyboardShortcut(.cancelAction)`.

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
- `NavigationSplitView` with sidebar tab list and `Form` detail using `.formStyle(.grouped)`.
- Minimum frame: `.frame(minWidth: 720, minHeight: 460)` with scene default size `720x460`.
- Dock visibility changes may reopen settings via `openWindow(id: "settings-window")` after activation policy updates.
- Screenshot, Video, and GIF settings each expose a per-type "show capture picker" toggle; default it to enabled so the current picker-first experience remains unchanged unless the user opts out.
- For MAS (`APPSTORE`): keep save location UI minimal and sandbox-safe (default Pictures/Movies behavior plus user-selected folder bookmark path display).

## Security

- Direct target entitlements: audio input, disabled library validation (for Sparkle), **not sandboxed**.
- MAS target entitlements: sandbox enabled, Pictures/Movies read-write, audio input, no Sparkle-related library validation bypass.
- Screen recording: dual-check — `CGPreflightScreenCaptureAccess()` first, then `SCShareableContent` query as fallback for macOS 15+ false negatives.
- Microphone: `NSMicrophoneUsageDescription` in Info.plist, requested at recording time via `AVCaptureDevice.requestAccess(for: .audio)`.
