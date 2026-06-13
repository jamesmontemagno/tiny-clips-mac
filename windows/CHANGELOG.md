# Changelog — Tiny Clips for Windows

All notable changes to the Windows (WinUI 3) port are documented here. The macOS app has its
own `CHANGELOG.md` at the repository root.

## [Unreleased]

### Added
- Region / Screen / Window **capture picker** shown before each capture, with `R` / `S` / `W`
  shortcuts and an inline pre-capture countdown (parity with the macOS picker).
- Per-window and per-monitor capture targets (`CaptureTarget`) wired through screenshot, video,
  and GIF pipelines.
- **Clips Manager** library window: Fluent grid of saved captures with image previews, a
  type/favorites filter, and per-clip open / show-in-Explorer / copy / delete actions.
- First-run **onboarding** wizard and an in-app **Guide** (help) window.
- Settings parity sections: **Mouse Clicks**, **Branding**, and a **Pro** status notice.
- **Pro feature gating** (`IEntitlementService` / `ProFeature`) for the direct build; mouse-click
  visuals, branding overlay, favorites, and upload are gated and surface an upsell when locked.
- `windows/docs/dpi-and-coordinates.md` documenting the pixel-vs-DIP capture strategy.
- **Screenshot editor** that opens after each screenshot (toggleable): drag-to-crop with
  apply/reset, copy to clipboard, save (overwrite), and save-a-copy. Also reachable from the
  Clips Manager **Edit** action on image clips.
- **Video trimmer** with a preview player and start/end range sliders that renders a trimmed
  `(trimmed)` MP4 via `MediaComposition`.
- **GIF trimmer** that drops leading/trailing frames and re-encodes a `(trimmed)` GIF with
  preserved per-frame delays.
- Settings toggles to open the editor / trimmers automatically after capture
  (**Screenshot**, **Video**, **GIF** sections).

### Notes
- Captures are recorded to the configured output folders and surfaced by the Clips Manager by
  scanning those folders — no separate database to keep in sync.
- Real-time mouse-click & branding compositing, microphone/system-audio muxing, and MSIX/Store
  packaging are **not yet implemented** in this port.

## [0.1.0] — Phase 1 capture core

### Added
- Tray-only WinUI 3 app with a Fluent menu, light/dark/system theming, and a custom tray icon.
- Screenshot (PNG/JPEG), drag-selected region capture, H.264 MP4 video, and animated GIF.
- Global hotkeys (`Ctrl+Shift+5/6/7`), pre-capture countdown, and save toast notifications.
- Native Settings window (General / Screenshot / Video / GIF / Shortcuts).
