# TinyClips for Windows — Multi-Monitor Support Plan

> **Status:** Planning only (approved scope, no implementation yet).
> **Branch target:** `jamesmontemagno/winui3-windows-port-plan`.
> This plan brings the Windows port to macOS parity for multi-display capture: pick **any**
> monitor for a full-screen capture, and **snip a region on any monitor** via a simultaneous
> overlay across every display. Indicators (countdown, recording, processing, region outline)
> follow the captured monitor instead of always landing on the primary display.

---

## 1. Goal & Confirmed Decisions

| Topic | Decision |
| --- | --- |
| **Region snip UX** | **macOS parity** — show the rubber-band overlay on **all monitors at once**. The user drags a region on whichever screen they want; no pre-selection / monitor-picker step for region mode. |
| **Full-screen "Screen" picker** | Already works well (centered list dialog when >1 display). **Don't redesign it** — only **audit/relocate the Cancel button** on `ScreenPickerWindow` so it's clearly placed. |
| **Indicators (countdown / recording / processing / region outline)** | **Follow the captured monitor** — position on/near the display being captured (or near the region), not always the primary work area. |
| **"Capture under cursor / always main display" shortcut option** | **Yes** — add a setting (macOS parity) so the global hotkeys can skip the picker and capture either the display under the mouse cursor or a fixed main display. |

---

## 2. Why this is mostly a UI/coordination task (not a pipeline rewrite)

The Windows capture pipeline is **already monitor-agnostic**. The heavy lifting is done:

- `IMonitorService.GetMonitors()` (`MonitorService.cs`) already enumerates **every** display via
  `EnumDisplayMonitors` + `GetMonitorInfo` + `GetDpiForMonitor`, returning each monitor's
  **virtual-desktop origin** (including negative X/Y for left-of / above-primary displays),
  width/height in physical pixels, per-monitor DPI, and `HMONITOR`. The app manifest is already
  `PerMonitorV2`.
- `ContinuousCaptureSession` (video/GIF) and `ScreenshotService` already accept a
  `CaptureTarget.Monitor(HMONITOR)` **plus an optional monitor-relative `PixelRect`** region and
  crop accordingly — for **any** monitor, not just primary.
- `RegionSelectWindow` is **already single-monitor-capable**: it pre-captures that monitor's
  backdrop (`CaptureMonitorAsync(HMONITOR)`), positions itself at the monitor's virtual-desktop
  origin (`AppWindow.Move(monitor.X, monitor.Y)`), sizes to the monitor, and returns a
  **monitor-relative** `PixelRect` in physical pixels using `RootGrid.XamlRoot.RasterizationScale`.
- `App.xaml.cs` already has `ToVirtualDesktopRegion(target, region)` to map a monitor-relative
  region into virtual-desktop coordinates (used for the region outline indicator).

**The only hardcoded-to-primary spot for region capture** is `App.xaml.cs ResolveTargetAsync`'s
`CapturePickerMode.Region` branch (lines ~415–427), which always calls
`monitors.GetPrimaryMonitor()` and shows a single `RegionSelectWindow` on the primary display.

So the work is:
1. Turn the single region overlay into **N coordinated overlays** (one per monitor) sharing one
   result, returning **which** monitor was chosen + the region on it.
2. **Reposition the indicators** onto the captured monitor.
3. Add the **"capture under cursor / always main display"** setting + hotkey fast-path.
4. **Audit** the screen picker's Cancel button.

### macOS reference model (for parity)
- mac shows a borderless region overlay on **every `NSScreen`** simultaneously (one window per
  screen at `.screenSaver` level); each returns a **display-local** rect + `CGDirectDisplayID` +
  `backingScaleFactor`. Finishing/Esc on any overlay tears down all of them.
- Windows equivalent: **`HMONITOR` is the display identity** (analogous to `CGDirectDisplayID`),
  `RasterizationScale` is the per-display scale (analogous to `backingScaleFactor`).

---

## 3. Coordinate-Space Cheatsheet (get this right or it breaks on mixed DPI)

| Space | Used by | Notes |
| --- | --- | --- |
| **Virtual desktop (physical px)** | `MonitorInfo.X/Y/Width/Height`, `AppWindow.Move/Resize`, capture crop on the whole-desktop | Origin = primary top-left; other monitors can be **negative**. |
| **Monitor-relative (physical px)** | `CaptureTarget` region, `RegionSelectWindow` result | `region.X/Y` are offsets **within** the chosen monitor. |
| **DIPs (per-window)** | XAML pointer coords inside each overlay | Multiply by that window's `XamlRoot.RasterizationScale` to get physical px. **Each overlay has its own scale** on mixed-DPI setups. |

**Rule:** each overlay converts its own pointer DIPs → physical px with **its own**
`RasterizationScale`. Never reuse the primary monitor's scale for a secondary monitor.

---

## 4. Design

### 4.1 Multi-monitor region overlay (the core change)

Introduce a coordinator that spawns one overlay per monitor and resolves a single result of
**(which monitor, region on that monitor)**.

**New type — `RegionSelectController`** (App layer; can live in `RegionSelectWindow.xaml.cs` or a
sibling file):

- `static Task<RegionSelectResult?> RunAsync(IReadOnlyList<MonitorInfo> monitors)`
  - Pre-capture each monitor's backdrop (parallel `CaptureMonitorAsync(HMONITOR)`), as `RunAsync`
    does today, so the dim panels are never baked into the snapshot.
  - Create one `RegionSelectWindow` per monitor, each positioned at its monitor origin and given
    its backdrop. **Share a single `TaskCompletionSource<RegionSelectResult?>`** across all of them.
  - **First completion wins:** when any overlay commits a region (pointer-up with a non-empty
    rect) or cancels (Esc / empty drag / lost activation), set the TCS once (guard with
    `Interlocked`/`_completed`) and **close every overlay**.
  - Return `new RegionSelectResult(monitor.HMonitor, monitorRelativeRect)` or `null` on cancel.

- **`RegionSelectResult`**: `record struct RegionSelectResult(nint HMonitor, PixelRect Region)`.

**Refactor `RegionSelectWindow`** to support being one-of-N:
- Change the private ctor / `RunAsync` so the window can be created with an **externally supplied**
  backdrop + a **shared completion callback** (instead of owning its own `TaskCompletionSource`).
  Simplest approach: add an internal `Action<RegionSelectResult?>` (or `onComplete`) the window
  invokes when the user finishes/cancels, and an internal `Close()` the controller calls to tear
  the others down. Keep the existing single-monitor `RunAsync(MonitorInfo)` as a thin wrapper over
  the controller (so any current single-monitor callers keep working), **or** replace its only
  caller (`ResolveTargetAsync`) directly.
- Each overlay still computes its region with **its own** `RootGrid.XamlRoot.RasterizationScale`.
- **Esc / empty drag on any monitor cancels the whole operation** (parity with macOS).
- **Cross-monitor drag (start on A, end on B)** is out of scope for v1 — each overlay handles
  only pointer events within its own window (which is how Win32 overlays naturally behave). The
  region is confined to the monitor where the drag started. Document this; revisit only if needed.

**Wire into `ResolveTargetAsync` (Region branch, ~415):**
```csharp
case CapturePickerMode.Region:
{
    var all = monitors.GetMonitors();
    if (all.Count == 0) return null;
    var result = await RegionSelectController.RunAsync(all);   // was: RegionSelectWindow.RunAsync(primary)
    return result is { } r
        ? new TargetSelection(CaptureTarget.Monitor(r.HMonitor), r.Region)
        : null;
}
```
The rest of the pipeline (`CaptureTarget.Monitor(HMONITOR)` + monitor-relative region) already
captures the correct display — **no capture-pipeline changes required.**

### 4.2 Indicators follow the captured monitor

All four indicators currently anchor to the **primary** work area
(`DisplayArea.Primary.WorkArea`). Add captured-monitor positioning variants. The captured monitor
is identified by the `HMONITOR` already flowing through the capture call; map it to a `MonitorInfo`
(`GetMonitors().First(m => m.HMonitor == hmon)`) to get its virtual-desktop bounds.

| Window | Current method | Change |
| --- | --- | --- |
| `CountdownWindow` | `CenterOnPrimaryDisplay()` | Add `CenterOnMonitor(MonitorInfo)` — center the rounded card on the captured monitor's bounds. (Remember: apply `SetWindowRgn`/positioning **after** `Activate()`, per the countdown blank-surface fix.) |
| `RecordingIndicatorWindow` | `PositionNearPrimaryWorkArea()` | Add `PositionNearMonitorWorkArea(MonitorInfo)` — anchor near the captured monitor's work-area corner. |
| `ProcessingIndicatorWindow` | `PositionNearPrimaryWorkArea()` | Same: `PositionNearMonitorWorkArea(MonitorInfo)`. |
| Region outline indicator | already uses `ToVirtualDesktopRegion` | Already correct — it maps the monitor-relative region to virtual-desktop coords. Verify it draws on the right monitor for negative-origin displays. |

- For **region** captures, prefer anchoring the recording/processing indicators **near the region**
  (use the region's virtual-desktop rect) rather than the monitor corner, to match the mac feel.
  Fall back to the monitor work-area corner for full-screen captures.
- Compute work-area insets per monitor. `MonitorInfo` exposes full monitor bounds; if a separate
  work-area (taskbar-excluded) rect isn't already available, derive it from `GetMonitorInfo`'s
  `rcWork` (extend `MonitorService` to surface `WorkArea` if not present). **Check `MonitorService`
  before adding** — it may already capture `rcWork`.
- Thread the captured `MonitorInfo` (or `HMONITOR`) from `ResolveTargetAsync` →
  `ShowRecordingIndicator` / `ShowProcessingIndicator` / countdown call sites so each can position
  correctly. For window-capture targets (no monitor), fall back to the monitor under the captured
  window, or primary.

### 4.3 "Capture under cursor / always main display" setting (hotkey fast-path)

macOS has `alwaysCaptureMainDisplay` / `screenUnderMouseCursor`. Add the Windows analogue so the
**global hotkeys** can skip the picker for full-screen/region capture and target a display
automatically.

- **New `ICaptureSettings` property**, e.g. `MultiMonitorCaptureMode` (string/enum persisted via
  `_settings.Get/Set`, following the existing key pattern like `"multiMonitorCaptureMode"`).
  Values:
  - `"picker"` (default) — current behavior (show picker / overlay on all monitors).
  - `"underCursor"` — target the monitor under the mouse cursor.
  - `"mainDisplay"` — always target the primary/main display.
- **Helper:** `IMonitorService.GetMonitorUnderCursor()` — `GetCursorPos` → `MonitorFromPoint`, map
  to a `MonitorInfo`. (Add to `MonitorService`.)
- **Apply** in the hotkey-triggered capture path:
  - For **Screen** (full-screen) hotkey: when mode is `underCursor` / `mainDisplay`, **skip
    `ScreenPickerWindow`** and use the resolved monitor directly.
  - For **Region** hotkey: when `underCursor` / `mainDisplay`, show the region overlay **only on
    that one monitor** (reuse the existing single-monitor path) instead of all monitors.
  - The tray-menu entries can keep showing the full picker/all-monitor overlay regardless (the
    setting is about the hotkey fast-path, matching mac), or honor the setting too — pick one and
    document it. **Recommendation:** honor the setting everywhere for consistency; the picker is
    still reachable by setting mode back to `"picker"`.
- **Settings UI:** add a control in the existing General/Screenshot area — a `ComboBox` /
  `RadioButtons` ("Show picker" / "Capture under cursor" / "Always main display") bound
  `TwoWay` via `SettingsViewModel`, with `AutomationProperties.AutomationId`. Match the macOS
  wording where reasonable.

### 4.4 Screen picker Cancel-button audit (minor)

- `ScreenPickerWindow` works; only **audit the Cancel button placement** (`OnCancel → Complete(null)`).
  Ensure it's a clearly positioned, full-size `Button` (not cramped/clipped), has
  `AutomationProperties.AutomationId`, is reachable by keyboard (Esc already cancels), and reads
  well in light/dark. Adjust layout/margins only — no behavior change.

---

## 5. Edge Cases & Risks

1. **Mixed-DPI correctness** — the #1 risk. Each overlay must use **its own**
   `RasterizationScale` for DIP→px. Test with two monitors at different scales (e.g. 100% + 150%)
   and confirm the captured region matches the rubber-band on **both**. Validate negative-origin
   monitors (display physically left of / above primary).
2. **Monitor hot-plug / removal mid-selection** — if a display is added/removed while the overlay
   is up, the snapshot set is stale. v1: snapshot the monitor list once at `RunAsync`; if a monitor
   disappears, its overlay closing should cancel gracefully (guard `Complete` once). Optionally
   subscribe to `WM_DISPLAYCHANGE` later to rebuild overlays — **defer** unless testing shows it's
   needed.
3. **Work-area vs full bounds** — full-screen capture should capture the **whole** monitor; the
   **indicators** should avoid the taskbar (use `rcWork`). Don't conflate the two.
4. **Window-capture target has no monitor** — indicators fall back to the monitor under the captured
   window (`MonitorFromWindow`) or primary.
5. **Per-overlay focus / activation** — N borderless top-most overlays: ensure the one the user
   interacts with has focus; Esc must cancel globally even if a non-focused overlay is hovered.
   Guard against double-completion across overlays (`Interlocked.Exchange`/`_completed` flag).
6. **Performance** — N parallel `CaptureMonitorAsync` backdrops on many-monitor rigs. Capture in
   parallel; it's a one-shot per monitor and acceptable, but cap/log if a capture fails (an overlay
   can still show a dim background without a backdrop, as the current null-backdrop path allows).
7. **`MonitorService.WorkArea`** — confirm whether `rcWork` is already surfaced; if not, extend
   `MonitorInfo` (additive, low risk; it's already populated by `GetMonitorInfo`).

---

## 6. Files to Touch (anchors)

| File | Change |
| --- | --- |
| `windows/src/TinyClips.App/RegionSelectWindow.xaml.cs` | Refactor to accept an external backdrop + shared completion callback; add `RegionSelectController.RunAsync(monitors)` + `RegionSelectResult`. Keep a single-monitor wrapper for the under-cursor/main-display fast-path. |
| `windows/src/TinyClips.App/App.xaml.cs` | `ResolveTargetAsync` Region branch → use the controller across all monitors; thread captured `MonitorInfo`/`HMONITOR` into `ShowRecordingIndicator`/`ShowProcessingIndicator`/countdown; apply the new capture-mode setting in the hotkey fast-path. |
| `windows/src/TinyClips.App/CountdownWindow.xaml.cs` | Add `CenterOnMonitor(MonitorInfo)` (positioning/clip after `Activate()`). |
| `windows/src/TinyClips.App/RecordingIndicatorWindow.xaml.cs` | Add `PositionNearMonitorWorkArea(MonitorInfo)` (+ optional near-region variant). |
| `windows/src/TinyClips.App/ProcessingIndicatorWindow.xaml.cs` | Add `PositionNearMonitorWorkArea(MonitorInfo)`. |
| `windows/src/TinyClips.App/ScreenPickerWindow.xaml(.cs)` | Audit/relocate Cancel button (layout only). |
| `windows/src/TinyClips.Core/Capture/MonitorService.cs` | Add `GetMonitorUnderCursor()`; surface `WorkArea` (`rcWork`) on `MonitorInfo` if not already present. |
| `windows/src/TinyClips.Core/Services/CaptureSettings.cs` (+ `ICaptureSettings`) | Add `MultiMonitorCaptureMode` setting (default `"picker"`). |
| `windows/src/TinyClips.App/ViewModels/SettingsViewModel.cs` + Settings XAML | Bind the new capture-mode control (TwoWay, AutomationId). |
| `windows/CHANGELOG.md` | Document multi-monitor region/screen capture + indicators-follow-display + capture-mode setting. |

---

## 7. Phased Delivery (suggested commit boundaries)

1. **Multi-monitor region overlay** — `RegionSelectController` + `RegionSelectWindow` refactor +
   `ResolveTargetAsync` wiring. Verify region capture on a secondary/negative-origin monitor.
   *(Largest, riskiest — do first and validate mixed-DPI.)*
2. **Indicators follow captured monitor** — countdown/recording/processing positioning variants +
   threading `MonitorInfo` through. Verify on each monitor.
3. **Capture-mode setting** — `MultiMonitorCaptureMode` + `GetMonitorUnderCursor()` + hotkey
   fast-path + Settings UI.
4. **Screen-picker Cancel audit** — layout polish (smallest).

Each step: build **x64** clean (0/0), boot-test (ALIVE), update `CHANGELOG.md`, commit + push
individually (stage by explicit path; Co-authored-by trailer).

---

## 8. Out of Scope (v1)

- **Cross-monitor region drag** (start on one display, finish on another). Each region is confined
  to the monitor where the drag begins.
- **Live hot-plug rebuild** of overlays while selection is open (snapshot once; cancel gracefully
  if a monitor vanishes).
- **Per-window capture exclusion** changes — unrelated to multi-monitor.
- ARM-specific tuning beyond a clean build.

---

## 9. Open Questions (none blocking — sensible defaults assumed)

- **Does the under-cursor/main-display setting apply to tray-menu actions too, or only hotkeys?**
  Assumed: **applies everywhere** for consistency (picker still reachable via `"picker"` mode).
  Flag if the maintainer wants hotkey-only (closer to the literal macOS behavior).
- **Indicator anchor for region captures** — assumed **near the region**; falls back to the
  captured monitor's work-area corner for full-screen.
