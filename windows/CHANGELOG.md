# Changelog — Tiny Clips for Windows

All notable changes to the Windows (WinUI 3) port are documented here. The macOS app has its
own `CHANGELOG.md` at the repository root.

## [Unreleased]

### Added
- **Mouse-click visual overlays** in video and GIF recordings: a global low-level mouse hook
  (`MouseClickMonitor`) records click timing/position, and `MouseClickOverlayCompositor` draws
  expanding, fading pulse rings into each captured frame (parity with the macOS
  `MouseClickOverlayProcessor`). Honors the per-type enable toggle and is gated to monitor/region
  targets (window targets are skipped, matching the mac restriction).
- Mouse-click **highlight color** setting with a live preview swatch in the Mouse Clicks section.
- Region / Screen / Window **capture picker** shown before each capture, with `R` / `S` / `W`
  shortcuts and an inline pre-capture countdown (parity with the macOS picker).
- Per-window and per-monitor capture targets (`CaptureTarget`) wired through screenshot, video,
  and GIF pipelines.
- First-run **onboarding** wizard and an in-app **Guide** (help) window.
- Settings parity sections: **Mouse Clicks**, **Branding**, and a **Pro** status notice.
- **Pro feature gating** (`IEntitlementService` / `ProFeature`) for the direct build; mouse-click
  visuals, branding overlay, and upload are gated and surface an upsell when locked.
- `windows/docs/dpi-and-coordinates.md` documenting the pixel-vs-DIP capture strategy.
- **Screenshot editor** that opens after each screenshot (toggleable): drag-to-crop with
  apply/reset, copy to clipboard, save (overwrite), and save-a-copy.
- **Video trimmer** with a preview player and start/end range sliders that renders a trimmed
  `(trimmed)` MP4 via `MediaComposition`.
- **GIF trimmer** that drops leading/trailing frames and re-encodes a `(trimmed)` GIF with
  preserved per-frame delays.
- Settings toggles to open the editor / trimmers automatically after capture
  (**Screenshot**, **Video**, **GIF** sections).
- Dedicated stop-recording hotkey (`Ctrl+Shift+S`) shown in the tray menu, recording indicator,
  and Guide.
- Region countdown indicator that outlines the selected capture region until recording or
  screenshot capture begins.
- **Recording indicator** — a floating always-on-top panel shown while recording video or GIF,
  with a live `MM:SS` elapsed timer, the stop hotkey, and a **Stop** button.
- **Launch at login** — optional setting that starts TinyClips when you sign in to Windows
  (via the `HKCU\...\Run` registry key).

### Changed
- **Settings** is now organized into a left **NavigationView** with one section per group
  (General, Screenshot, Video, GIF, Mouse Clicks, Branding, Hotkeys, Pro).
- **Pro features are unlocked** in the direct (non-Store) build, matching the macOS direct
  distribution; the Store build will gate them via a StoreContext-backed entitlement service.
- **Region selector** now shows a live snapshot of the screen behind a hole-punch dim, so the
  area being captured stays clear and fully visible (instead of dimming the whole screen).
- **Screen** and **Window** pickers are now compact, centered dialogs that leave the rest
  of the desktop visible rather than graying out the entire display.
- The capture picker, the pickers, and the countdown now use a translucent **acrylic** backdrop
  so the desktop shows through; the **countdown** is a smaller circle.
- The **capture picker** and the **recording indicator** can be dragged to reposition them.
- New **app icon** (512px base + refreshed MSIX tiles) recreating the viewfinder mark crisply.
- **Trimmers** redesigned with a cleaner preview / trim-range / footer layout and a **Speed**
  control (GIF output speed is applied to frame delays; video speed currently affects preview).
- A new **Reopen capture picker after each capture** setting re-shows the picker when a capture
  finishes.

### Fixed
- **Tray menu was clipped on its first open** — the SecondWindow context menu is now
  warmed up invisibly at startup (DWM-cloaked) so the first menu is measured at the correct
  display scale instead of being cut off at the bottom.
- **Drag jitter** when moving the capture picker and recording indicator — dragging is now
  cursor-anchored, so the windows follow the pointer smoothly instead of jumping.
- **Screenshot editor crash** — removed a reference to a nonexistent WinUI resource key
  (`AccentFillColorSelectedContentBackgroundBrush`) that threw during XAML parse and silently
  prevented the editor from opening; opening is also now wrapped with a reveal/toast fallback.
- **Countdown** is now a compact rounded square instead of a large background panel.
- **Region outline is now hollow** (a punched-out frame) so the content being recorded is
  visible through the middle.
- **Recorded MP4 was vertically flipped** — video frames are now written with the correct
  top-down orientation (the GIF path was already correct).
- **Screenshot editor** now reliably opens and comes to the foreground after a screenshot.
- The screen is **no longer dimmed** between finishing a region selection and the recording
  starting for video/GIF.
- A **region outline** now stays visible (click-through and excluded from capture) while
  recording a region, and the outline is drawn just outside the captured area.
- The **recording indicator** is excluded from capture so it no longer appears in recordings.
- Quitting the app while a **GIF** recording is active now finalizes the GIF instead of
  abandoning it, and the exit path no longer blocks the UI thread.
- Launch-at-login registry value is now **quoted** so executable paths with spaces work.
- Hotkey labels now render punctuation/symbol keys (e.g. `-`, `=`, `,`) instead of `?`.

### Removed
- The redundant **Capture Region** item from the tray menu; region capture is still available
  via the **Capture Screenshot** flow's picker (`R`).
- The **Clips Manager** library window (and its `ClipTile` view-model) for now; captures still
  save to the configured output folders and surface via Explorer + save toasts.

### Notes
- Captures are recorded to the configured output folders and surfaced by save toasts /
  reveal-in-Explorer — no separate database to keep in sync.
- Real-time mouse-click & branding compositing, microphone/system-audio muxing, and MSIX/Store
  packaging are **not yet implemented** in this port.

## [0.1.0] — Phase 1 capture core

### Added
- Tray-only WinUI 3 app with a Fluent menu, light/dark/system theming, and a custom tray icon.
- Screenshot (PNG/JPEG), drag-selected region capture, H.264 MP4 video, and animated GIF.
- Global hotkeys (`Ctrl+Shift+5/6/7`), pre-capture countdown, and save toast notifications.
- Native Settings window (General / Screenshot / Video / GIF / Shortcuts).
