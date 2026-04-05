# TinyClips — Project Guidelines

TinyClips is a macOS menu bar app for screen capture (screenshots, video, GIF). It targets **macOS 15.0+**, uses **Swift 5** with an Xcode project (no Package.swift), and has **Sparkle** as its only dependency (via SPM) for direct distribution builds.

Two app variants share one codebase:
- **`TinyClips`** — Direct distribution (non-sandboxed, Sparkle-enabled)
- **`TinyClipsMAS`** — Mac App Store (sandboxed, no Sparkle, `APPSTORE` compilation condition)

See `CONTRIBUTING.md` for full setup, project structure, and contribution workflow.

## Architecture

- **Menu bar app** — SwiftUI `MenuBarExtra` + SwiftUI `Window` scenes (`"clips-manager"`, `"settings-window"`). No Dock icon by default (`LSUIElement = true`).
- **Mixed SwiftUI + AppKit** — SwiftUI for menu bar, settings, Clips Manager; AppKit `NSWindow`/`NSPanel` subclasses for capture-time windows. AppKit windows host SwiftUI views via `NSHostingView`.
- **`CaptureManager`** in `TinyClipsApp.swift` is the central coordinator owning recorders, writers, and all capture-time window lifecycles.
- **Singleton services**: `CaptureSettings.shared`, `SaveService.shared`, `PermissionManager.shared`, `SparkleController.shared`, `StoreService.shared` (MAS only).
- **Pro features** (MAS): gate on `StoreService.shared.isPro`. `StoreService` uses StoreKit 2 with `ProPlan` enum (monthly/yearly/lifetime). Guard pro UI with `#if APPSTORE`.

## Code Style

- `ObservableObject` / `@Published` / `@StateObject` — **not** `@Observable` (Observation framework).
- `@AppStorage` for all user preferences (see `TinyClips/Models/CaptureSettings.swift`).
- `@MainActor` on all UI-facing classes. `@unchecked Sendable` + `DispatchQueue` for off-main-thread capture classes. No actors or `@Sendable` closures.
- `// MARK: -` comments for section organization within files.
- SwiftUI views inside window files as `private struct`.
- `popover(item:)` over `popover(isPresented:)` for data-dependent popovers.
- `#if canImport(Sparkle)` to guard Sparkle imports. `#if APPSTORE` for MAS-specific behavior.
- Closures/callbacks for inter-component communication — no `NotificationCenter` posting.
- `withCheckedContinuation` / `withCheckedThrowingContinuation` to bridge callback APIs to async.
- Single `CaptureError` enum conforming to `LocalizedError`; surface via `SaveService.shared.showError()`.

## Build and Test

```bash
# Build both variants (CI, no signing) — always validate BOTH schemes
xcodebuild build -project TinyClips.xcodeproj -scheme TinyClips -configuration Debug \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
xcodebuild build -project TinyClips.xcodeproj -scheme TinyClipsMAS -configuration Debug \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

- No test target exists.
- CI (`.github/workflows/build.yml`) runs both scheme builds on PRs to `main`/`develop`.
- **Agent sandbox caveat**: if `xcodebuild` fails with `Operation not permitted` or SwiftPM write errors (e.g., `sparkle.dia`), rerun unsandboxed.

## Conventions

### Windows
- **SwiftUI `Window` scenes** for long-lived windows (`clips-manager`, `settings-window`). **AppKit subclasses** for capture-time panels.
- Open scene windows via `openWindow(id:)`, then activate + bring to front with dual-pass (immediate + 0.1s delay to escape menu tracking timing).
- Callback-driven AppKit windows: keep a completion closure, guard with `didComplete`/`didClose` to prevent double-callbacks, set `isReleasedWhenClosed = false`, nil out callbacks after firing. `nil` payload = cancelled.
- `CaptureManager` holds strong refs to capture-time windows; defers `nil` releases with `DispatchQueue.main.async` to avoid deallocation mid-callback.
- Floating panels use borderless non-activating style at `.floating` level. See existing panels for the recipe.

### Capture Flows
Three capture types (screenshot, video, GIF) follow: permission → optional picker → optional region/screen selection → capture/record → optional editor/trimmer → save. Editor/trimmer windows open **after** recording resources are released. See `CONTRIBUTING.md` for detailed flow diagrams.

### Accessibility
Treat accessibility as a release gate. Add `.accessibilityLabel`/`.accessibilityHint`/`.accessibilityValue` for icon-only buttons, custom controls, and stateful UI. Ensure keyboard alternatives. Validate on both schemes with VoiceOver. See `CONTRIBUTING.md` for full guidelines.

### File Naming & Save
Output: `TinyClips yyyy-MM-dd 'at' HH.mm.ss.{ext}`. Trimmed files get ` (trimmed)` suffix. Cancelled edits clean up temp files. Post-save notifications use `UserNotifications` framework.

### Keyboard Shortcuts
Screenshot `⌃⌥⌘5`, Video `⌃⌥⌘6`, GIF `⌃⌥⌘7`, Stop `⌘.`. Picker: `R`/`S`/`W`/`Esc`. Registered via Carbon `RegisterEventHotKey` in `HotKeyManager`. Custom key recording via `ShortcutRecorderField`.

### PR Checklist
- Both `TinyClips` and `TinyClipsMAS` schemes must build.
- Update `CHANGELOG.md` (Added/Improved/Fixed).
- Guard Sparkle with `#if canImport(Sparkle)` — never link to MAS target.
- Verify accessibility with VoiceOver + keyboard on critical paths.

## Documentation Reference

| Doc | Topic |
|-----|-------|
| `CONTRIBUTING.md` | Setup, project structure, architecture, code style, contribution workflow |
| `docs/sparkle-setup.md` | Adding Sparkle dependency for direct distribution |
| `docs/app-store-variant-setup.md` | MAS target Xcode wiring, entitlements, sandbox |
| `docs/subscription-and-clips-setup.md` | StoreKit setup, Pro gating, Uploadcare integration |
| `docs/retina-display-capture.md` | Point vs pixel coordinates, `scalesToFit` strategy |
| `docs/app-store-connect-metadata.md` | App Store Connect listing metadata |

## Security

- Direct target: hardened runtime, audio input entitlement, disabled library validation (Sparkle). **Not sandboxed.**
- MAS target: sandboxed, Pictures/Movies read-write, audio input.
- Screen recording permission: dual-check — `CGPreflightScreenCaptureAccess()` then `SCShareableContent` query (macOS 15+ false-negative fallback).
- Microphone: `AVCaptureDevice.requestAccess(for: .audio)` at recording time.
