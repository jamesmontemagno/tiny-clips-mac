# Contributing to TinyClips

Thank you for your interest in contributing to TinyClips! This guide covers everything you need to get started.

## Table of Contents

- [Requirements](#requirements)
- [Project Setup](#project-setup)
- [Project Structure](#project-structure)
- [Development Tips](#development-tips)
- [Contribution Workflow](#contribution-workflow)
- [Pull Request Guidelines](#pull-request-guidelines)
- [Code Style](#code-style)
- [Reporting Bugs](#reporting-bugs)

---

## Requirements

- **macOS 15.0 (Sequoia)** or later
- **Xcode 16.0** or later
- An Apple Developer account (needed for screen recording entitlements when running locally)

---

## Project Setup

### 1. Fork and clone the repository

```bash
git clone https://github.com/<your-username>/tiny-clips-mac.git
cd tiny-clips-mac
```

### 2. Open the project in Xcode

```bash
open TinyClips.xcodeproj
```

### 3. Add the Sparkle dependency (direct distribution target only)

Sparkle is **not** committed to the repository and must be added via Xcode:

1. Go to **File → Add Package Dependencies…**
2. Enter URL: `https://github.com/sparkle-project/Sparkle`
3. Select **Up to Next Major Version** from `2.8.1`
4. Add the `Sparkle` framework to the **`TinyClips`** target only (not `TinyClipsMAS`)

See [docs/sparkle-setup.md](docs/sparkle-setup.md) for full details.

### 4. Select a scheme and run

| Scheme | Description |
|--------|-------------|
| `TinyClips` | Direct distribution — non-sandboxed, Sparkle-enabled |
| `TinyClipsMAS` | Mac App Store — sandboxed, no Sparkle |

Press **⌘R** to build and run the selected scheme.

### Building without code signing (CI / headless)

```bash
# Direct distribution
xcodebuild build -project TinyClips.xcodeproj -scheme TinyClips -configuration Debug \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# Mac App Store variant
xcodebuild build -project TinyClips.xcodeproj -scheme TinyClipsMAS -configuration Debug \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

### Permissions

TinyClips requires **Screen Recording** permission at runtime. On first launch, macOS will prompt you to grant access in **System Settings → Privacy & Security → Screen Recording**.

---

## Project Structure

```
TinyClips/
├── TinyClipsApp.swift          # App entry point, MenuBarExtra, CaptureManager
├── Models/
│   ├── CaptureSettings.swift   # @AppStorage settings model and shared types
│   └── ClipItem.swift          # Model for saved clips
├── Capture/
│   ├── RegionSelector.swift    # Fullscreen overlay for region selection
│   ├── ScreenshotCapture.swift # SCScreenshotManager → PNG
│   ├── VideoRecorder.swift     # SCStream → AVAssetWriter → MP4
│   └── GifWriter.swift         # SCStream → CGImageDestination → GIF
├── Services/
│   ├── SaveService.swift       # File saving, clipboard, Finder, notifications
│   ├── PermissionManager.swift # Screen recording permission handling
│   ├── SparkleController.swift # Sparkle auto-update integration
│   ├── StoreService.swift      # StoreKit subscription management
│   └── ProManager.swift        # Pro feature gating (MAS only)
└── Views/
    ├── SettingsView.swift       # Settings window
    ├── ClipsManagerWindow.swift # Clips Manager window
    ├── VideoTrimmerWindow.swift # Post-recording trim editor
    ├── CapturePickerPanel.swift # Floating mode/countdown picker
    ├── ScreenPickerWindow.swift # Multi-display screen picker
    ├── RegionIndicatorPanel.swift # Red region outline overlay
    ├── StartRecordingPanel.swift  # Floating record panel
    ├── StopRecordingPanel.swift   # Floating stop panel
    └── ...
docs/                           # Additional setup guides
```

Two build targets share one codebase. Use `#if APPSTORE` compilation conditions for any Mac App Store–specific behavior and `#if canImport(Sparkle)` to guard Sparkle imports.

---

## Development Tips

### Architecture overview

- **Menu bar app** using SwiftUI `MenuBarExtra` with no Dock icon (`LSUIElement = true`).
- **Mixed SwiftUI + AppKit**: SwiftUI for the menu, settings, and Clips Manager; AppKit `NSWindow`/`NSPanel` subclasses for capture-time overlays.
- **`CaptureManager`** (in `TinyClipsApp.swift`) is the central coordinator that owns recorders and capture window lifecycles.
- Singleton services: `CaptureSettings.shared`, `SaveService.shared`, `PermissionManager.shared`, `SparkleController.shared`.

### Key conventions

- Use `ObservableObject` / `@Published` / `@StateObject` — **not** the `@Observable` macro.
- Use `@AppStorage` for all user preferences (see `CaptureSettings.swift`).
- Mark all UI-facing classes `@MainActor`. Use `@unchecked Sendable` + `DispatchQueue` for off-main-thread capture classes.
- Use `// MARK: -` comments for section organization within files.
- Single `CaptureError` enum conforming to `LocalizedError`; surface errors via `SaveService.shared.showError()`.

### Accessibility

Accessibility is treated as a release gate. When adding or changing UI:

- Add explicit `.accessibilityLabel`, `.accessibilityHint`, and `.accessibilityValue` on icon-only buttons, custom controls, toggles, and stateful elements.
- Ensure custom controls have keyboard alternatives (default/cancel shortcuts, `Esc` cancel paths).
- Validate both `TinyClips` and `TinyClipsMAS` schemes with VoiceOver and keyboard-only navigation.

### Capture flows

1. **Screenshot:** permission → picker (region/screen/window + countdown) → optional screen picker for multi-display → optional region indicator → capture → optional editor → save.
2. **Video/GIF:** permission → picker → optional region indicator → start panel → optional countdown → record → stop panel → optional trimmer → save.

---

## Contribution Workflow

1. **Check existing issues** — search open issues before opening a new one or starting work.
2. **Open or claim an issue** — comment on the issue you intend to work on so others know it's in progress.
3. **Create a feature branch** off `main`:
   ```bash
   git checkout -b feature/short-description
   ```
4. **Make your changes** following the code style guidelines below.
5. **Build both schemes** to confirm nothing is broken:
   ```bash
   xcodebuild build -project TinyClips.xcodeproj -scheme TinyClips -configuration Debug \
     CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

   xcodebuild build -project TinyClips.xcodeproj -scheme TinyClipsMAS -configuration Debug \
     CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
   ```
6. **Push your branch** and open a pull request against `main`.

---

## Pull Request Guidelines

- **One concern per PR** — keep pull requests focused on a single feature, fix, or improvement.
- **Descriptive title** — use a short, imperative sentence (e.g., "Add countdown timer to GIF picker").
- **Fill in the PR description** — explain *what* changed and *why*. Link the related issue with `Closes #123`.
- **Both schemes must build** — the CI workflow builds both `TinyClips` and `TinyClipsMAS`; ensure your changes compile under both.
- **No Sparkle in `TinyClipsMAS`** — guard any Sparkle references with `#if canImport(Sparkle)` or `#if !APPSTORE`.
- **Update the CHANGELOG** — add an entry under the appropriate section (`Added`, `Improved`, or `Fixed`) in `CHANGELOG.md`.
- **Accessibility** — if your change affects any UI, verify it works with VoiceOver and keyboard-only navigation.
- **Small, incremental commits** — prefer clear, atomic commits with descriptive messages.

---

## Code Style

- **Swift 5**, targeting macOS 15.0+.
- Follow the existing file and naming conventions — see the `// MARK: -` section organization in existing files as a reference.
- Keep SwiftUI views defined as `private struct` inside their window/panel file.
- Use `popover(item:)` over `popover(isPresented:)` for data-dependent popovers.
- Prefer closures/callbacks for inter-component communication — no `NotificationCenter` posting.
- Use `withCheckedContinuation` / `withCheckedThrowingContinuation` to bridge callback APIs to `async/await`.
- Output file names follow the pattern `TinyClips yyyy-MM-dd 'at' HH.mm.ss.{ext}`.

---

## Reporting Bugs

Please use the **[bug report template](.github/ISSUE_TEMPLATE/bug_report.yml)** when opening a new issue. Include:

- macOS version
- TinyClips version
- Steps to reproduce
- Expected vs. actual behavior
- Any relevant logs or screenshots

---

*Thank you for helping make TinyClips better!*
