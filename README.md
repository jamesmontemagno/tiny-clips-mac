# TinyClips for macOS

[![Build](https://github.com/jamesmontemagno/tiny-clips-mac/actions/workflows/build.yml/badge.svg)](https://github.com/jamesmontemagno/tiny-clips-mac/actions/workflows/build.yml)
[![Release](https://github.com/jamesmontemagno/tiny-clips-mac/actions/workflows/release.yml/badge.svg)](https://github.com/jamesmontemagno/tiny-clips-mac/actions/workflows/release.yml)
[![GitHub release](https://img.shields.io/github/v/release/jamesmontemagno/tiny-clips-mac?style=flat-square)](https://github.com/jamesmontemagno/tiny-clips-mac/releases/latest)
![macOS](https://img.shields.io/badge/macOS-15.0+-blue?style=flat-square&logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9-orange?style=flat-square&logo=swift)
[![License: MIT](https://img.shields.io/github/license/jamesmontemagno/tiny-clips-mac?style=flat-square)](LICENSE)

A lightweight macOS menu bar app for capturing screenshots (PNG), video (MP4), and animated GIFs of a selected screen region.

![](./docs/tinyclips.png)

## Features

- **Screenshot** — Select a region and capture a PNG screenshot
- **Video Recording** — Record a screen region to MP4 with H.264 encoding
- **GIF Recording** — Record a screen region as an animated GIF
- **Video Trimmer** — Built-in trim editor to cut the start/end before saving
- **Menu Bar App** — Lives in the menu bar with no Dock icon
- **Region Selection** — Drag to select any portion of any screen
- **Auto-Updates** — Built-in Sparkle integration for seamless updates
- **Configurable** — Save location, clipboard, Finder reveal, GIF quality, trimmer toggle

## Requirements

- macOS 15.0 (Sequoia) or later
- Xcode 16.0 or later

## Installation

### Download

Download the latest release from the [Releases](https://github.com/jamesmontemagno/tiny-clips-mac/releases) page.

### Build from Source

1. Clone the repository:
   ```bash
   git clone https://github.com/jamesmontemagno/tiny-clips-mac.git
   cd tiny-clips-mac
   ```

2. Open in Xcode:
   ```bash
   open TinyClips.xcodeproj
   ```

3. Add Sparkle package dependency (see [Sparkle Setup](#sparkle-setup))

4. Build and run (⌘R)

## Usage

1. Click the camera icon in the menu bar
2. Choose **Screenshot**, **Record Video**, or **Record GIF**
3. Drag to select a screen region
4. For video/GIF: click the floating **Stop** button when done

### Keyboard Shortcuts (in menu)

| Action | Shortcut |
|--------|----------|
| Screenshot | ⇧⌘5 |
| Record Video | ⇧⌘6 |
| Record GIF | ⇧⌘7 |
| Stop Recording | ⌘. |
| Settings | ⌘, |

### Settings

| Option | Description |
|--------|-------------|
| Save Directory | Where captures are saved (default: Desktop) |
| Copy to Clipboard | Auto-copy captures to clipboard |
| Show in Finder | Reveal saved file in Finder |
| GIF Frame Rate | 5–30 fps (default: 10) |
| GIF Max Width | 320–1920 px (default: 640) |
| Video Frame Rate | 24, 30, or 60 fps |
| Open Trimmer | Show trim editor after video recording |

## Permissions

TinyClips requires **Screen Recording** permission. On first launch, macOS will prompt you to grant access. After granting, restart the app.

## Sparkle Setup

Sparkle must be added manually via Xcode:

1. Open `TinyClips.xcodeproj` in Xcode
2. Go to **File → Add Package Dependencies...**
3. Enter URL: `https://github.com/sparkle-project/Sparkle`
4. Select version rule: **Up to Next Major Version** from `2.8.1`
5. Add the `Sparkle` framework to the `TinyClips` target

See [docs/sparkle-setup.md](docs/sparkle-setup.md) for full setup including key generation.

## App Store Variant

To ship both a direct (Sparkle, non-sandbox) build and a Mac App Store (sandboxed, no Sparkle) build from one codebase, see [docs/app-store-variant-setup.md](docs/app-store-variant-setup.md).

### Xcode Cloud

This project uses a hybrid CI/CD setup:

- GitHub Actions for direct distribution build/release (`TinyClips`)
- Xcode Cloud for Mac App Store build/distribution (`TinyClipsMAS`)

For App Store variant details and Xcode Cloud notes, see [docs/app-store-variant-setup.md](docs/app-store-variant-setup.md).

## Architecture

```
ScreenCaptureKit (SCStream / SCScreenshotManager)
       │
       ├── ScreenshotCapture → CGImageDestination → PNG
       ├── VideoRecorder → AVAssetWriter → MP4
       └── GifWriter → CGImageDestination → GIF
```

### Key Components

| File | Purpose |
|------|---------|
| `TinyClipsApp.swift` | App entry, MenuBarExtra, CaptureManager |
| `RegionSelector.swift` | Fullscreen NSWindow overlay for region selection |
| `ScreenshotCapture.swift` | SCScreenshotManager → PNG |
| `VideoRecorder.swift` | SCStream → AVAssetWriter → MP4 |
| `GifWriter.swift` | SCStream → CGImageDestination → GIF |
| `VideoTrimmerWindow.swift` | Post-recording trim editor for videos |
| `CaptureSettings.swift` | Shared types + @AppStorage settings model |
| `SaveService.swift` | File saving, clipboard, Finder, notifications |
| `PermissionManager.swift` | Screen recording permission handling |
| `SparkleController.swift` | Sparkle auto-update integration |

## License

MIT License. See [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome! Please feel free to submit a [Pull Request](https://github.com/jamesmontemagno/tiny-clips-mac/pulls).

Found a bug or have a feature request? [Open an issue](https://github.com/jamesmontemagno/tiny-clips-mac/issues/new).
