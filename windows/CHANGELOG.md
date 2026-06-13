# Changelog — Tiny Clips for Windows

All notable changes to the Windows (WinUI 3) port are documented here. The macOS app has its
own `CHANGELOG.md` at the repository root.

## [Unreleased]

### Changed
- **More speed presets for video & GIF trimmers** — the playback/output speed dropdown now offers
  finer and wider steps (0.1x, 0.25x, 0.5x, 0.75x, 1x, 1.25x, 1.5x, 1.75x, 2x, 2.5x, 3x, 4x, 5x)
  instead of the previous six, defaulting to 1x.
- **Countdown overlay redesigned (clean rounded square)** — the pre-capture countdown is now a
  single rounded-**square** card with a big centered number and a subtle accent border. The old
  circular clip + inner ring (which read as a "box in a box") was removed; the window is clipped
  to the same rounded square as the card so it fills edge-to-edge. Still excluded from recordings
  and hidden before the first captured frame.
- **System-tray popup redesigned (PowerToys-style)** — clicking the tray icon (left or right)
  now opens a compact custom popup with the three primary capture actions (Screenshot, Video,
  GIF) as large tiles across the top and a row of small icon buttons (Settings, Guide, Exit)
  at the bottom, instead of a vertical context menu. The popup is a borderless acrylic window
  anchored next to the cursor that light-dismisses on focus loss. This also resolves the
  first-open clipping seen with the previous `MenuFlyout`-based menu on high-DPI displays.
- **Screenshot editor: redesigned layout (left tool rail + inspector)** — tools now live in a
  vertical rail on the left with a contextual **inspector** panel beside them (mirroring the macOS
  app), and the output actions (Apply crop, Undo, Delete, Reset, Copy, Save) sit in a top bar.
  Selecting an annotation loads its properties into the inspector so they can be re-edited.
- **Screenshot editor: continuous sizes** — stroke width (1–40 px), number-badge size (50%–400%),
  and text font size (10–200 px) are now sliders instead of fixed presets.
- **No Pro gating on Windows** — the Pro concept was removed entirely from the Windows app. All
  features (mouse-click overlays, separate GIF click styles, branding, uploads, etc.) are always
  available; the Pro settings section, upsell banners, and the `IEntitlementService`/`ProFeature`
  abstraction were deleted to keep the app simple.

### Fixed
- **Screenshot editor: background panel clipping** — the Background expander's padding/corner/shadow
  sliders and style dropdown were cut off on the right edge of the inspector; the panel now stretches
  to fit and no longer overflows.
- **Screenshot editor: tool rail clipping** — the vertical tool rail is now scrollable, so the
  lower tools (Draw, Text, Number, Redact) are no longer cut off on shorter editor windows.
- **Screenshot editor: arrow/line crash** — drawing an arrow or line that pointed up or to the
  left crashed the app (`ArgumentOutOfRangeException` from a negative-size `Rect`). Lines and
  arrows are now stored as directed endpoints and render correctly in any direction.
- **Screenshot editor: editor failed to open** — the redesigned inspector sliders fired their
  `ValueChanged` handlers during XAML load (before controls existed), throwing a
  `NullReferenceException`/`XamlParseException` so the editor never appeared after a capture or via
  "Open with Tiny Clips". The initialization guard now defaults on.

### Added
- **Trimmers: export the current frame as a PNG** — both the video and GIF trimmers now have an
  **Export frame** button that saves the frame currently shown as a still PNG into the Tiny Clips
  folder (with a save notification). For video, the frame is extracted at the exact paused
  position; for GIF, the exact frame on screen.
- **Trimmers: frame stepper** — left/right step buttons move the preview one frame at a time. The
  GIF trimmer adds a current-frame scrubber + "Frame X / N" readout; the video trimmer nudges the
  paused position by a frame and shows the current position.
- **Screenshot editor: image dimensions** — the editor's top bar now shows the current image
  size (`W × H px`) on the right, updating after a crop is applied.
- **Screenshot editor: shape fill color** — rectangles and ellipses can now be filled with a
  color (with adjustable opacity). Fill is **off (transparent) by default**; enable it and pick a
  color in the inspector.
- **Screenshot editor: text font & color controls** — the Text tool now lets you pick a font
  family and size; numbered badges have an independent **number color** (default white) on top of
  the badge fill color.
- **Screenshot editor: Shift to constrain** — hold **Shift** while drawing a rectangle/ellipse for
  a perfect square/circle, or while drawing a line/arrow to snap to horizontal, vertical, or 45°.
- **Screenshot editor: export background, padding, corners & shadow** — a new **Background**
  toolbar control adds a styled backdrop behind the screenshot (Transparent, Solid, or Gradient)
  with 12 solid + 12 gradient presets and a custom color picker, plus **Padding** (0–160 px),
  **Corner radius** (0–60 px), and **Shadow** (0–40) sliders. The screenshot is rendered as a
  rounded, elevated card composited over the chosen background at full resolution on save/copy,
  mirroring the macOS editor's export background feature.
- **Screenshot editor: redaction strength & number-size levels** — the Redact tool now offers
  **Light / Medium / Heavy** blur strength and the Number badge tool offers **50%–200%** size
  presets, both shown contextually in the toolbar (mirrors the macOS app's inspector controls).
- **Screenshot editor: real fuzzy redaction** — redaction now applies a true Gaussian blur of
  the underlying content (intensity driven by the chosen level) in both the live preview and the
  saved/exported image, replacing the previous flat translucent block.
- **Programmable keyboard shortcuts** — the Screenshot, Record video, and Record GIF global
  shortcuts can now be reassigned from Settings (click **Edit**, then press a combination that
  includes Ctrl/Alt/Shift/Win) or **Reset** to the defaults; changes re-register the global
  hotkeys immediately.
- **Per-capture video time limit** — the capture picker now has a time-limit dropdown for video
  (No limit / 1 / 2 / 5 / 10 / 15 / 30 min) that overrides the default from Settings for that
  recording.
- **Open with Tiny Clips** — image files (.png/.jpg/.jpeg) can be opened directly in the
  screenshot editor via the Windows "Open with" menu (file-type association in the package).
- **Microphone device picker** — when "Record microphone" is on you can now choose which input
  device is recorded (defaults to the system default) in the Video settings.
- **Separate Video and GIF mouse-click styles** — the Mouse Clicks settings now have independent
  size, opacity, and color controls for video versus GIF recordings, each with a Fluent
  **color picker** (the GIF group is disabled while "GIF uses video click settings" is on).
- **GIF trimmer preview playback** — a play/pause toggle animates the selected frame range in the
  GIF trimmer, honoring per-frame delays and the chosen output speed so you can preview the result
  before saving.
- **Screenshot editor annotations** — parity with the macOS editor: rectangle, ellipse, arrow,
  line, freehand draw, text, numbered badges, and pixelated redaction, on top of the existing
  crop. Each annotation has a color picker and stroke-thickness selector; annotations can be
  selected, moved, deleted, and undone. Single-key tool shortcuts (V/C/R/O/A/L/D/T/N/B),
  `Ctrl+Z` undo and `Del` to remove the selection. Annotations preview live as XAML shapes and
  are baked into the image at full resolution with Win2D so the saved/copied PNG or JPEG matches
  the preview exactly.
- **Audio recording for video** — microphone and/or system ("desktop"/loopback) audio is now
  captured via WASAPI (NAudio), mixed and resampled to 48 kHz / 16-bit stereo, and muxed into the
  recorded MP4 as an AAC track. Honors the existing **Record system audio** / **Record microphone**
  toggles and the microphone device picker; each source is best-effort (a denied mic still records
  system audio, and vice-versa). GIFs remain silent. Adds the `microphone` device capability to the
  package manifest. *(A/V sync needs an on-hardware listen test — cannot be validated in CI.)*
- **Copy video / GIF to clipboard** settings — recorded MP4s and GIFs can now be copied to the
  clipboard (as a file) automatically after capture, alongside the existing screenshot copy
  (which also places the bitmap for direct paste). Toggles added to the Video and GIF sections.
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
- **Screenshot editor toolbar** is now cleaner and contextual — the stroke-thickness, number-size,
  and redaction-strength controls show only for the tools they apply to, and the stroke widths now
  match the macOS app's **1 / 2 / 4 / 6 / 8 / 10 px** options.
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
- The **screenshot editor and video/GIF trimmers** now open maximized (full screen) for more
  working room.

### Fixed
- **Screenshot editor text entry** — clicking to place a text annotation no longer immediately
  dismisses the text box. Focus is now deferred past the pointer interaction and the transient
  focus-loss is ignored, so you can type; **Enter** commits and **Esc** cancels.
- **Countdown lingered in recordings** — the countdown badge now hides itself before the final
  frame and is excluded from screen capture, so it no longer appears in the recorded video/GIF and
  no longer hangs at "1".
- **Countdown styling** — redesigned as a clean circular badge (acrylic, clipped to a true circle
  with a thin accent ring) instead of the previous "box in a box" look.
- **Recording region outline** is now a bright, thicker red so it is clearly visible while
  recording a region.
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
