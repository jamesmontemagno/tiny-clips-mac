# TinyClips for Windows — WinUI 3 Port Plan

> Status: **Planning (approved)** · Stack: **C# + WinUI 3 / Windows App SDK** · Target: **Windows 11 22H2 (22621+)**
>
> This plan was hardened over three adversarial review rounds (see [Appendix A](#appendix-a--review-history)).
> It maps the macOS TinyClips app to a Windows-native WinUI 3 implementation with maximum feature parity,
> native theming, a system-tray experience, and a packaging/distribution path to **winget + direct MSIX** first
> and the **Microsoft Store** soon after.
>
> **Scope update (post-implementation):** the **Clips Manager library** and **upload/Uploadcare**
> integration have been **removed from scope** — captures are browsed via File Explorer ("Show in
> Explorer" after each capture) and there is no in-app sharing/upload. The SQLite clip catalog is
> therefore not needed (prefs live in `LocalSettings`). Auto-update for the Direct build is handled
> entirely through **winget** (see [§4 Phase 4](#phase-4--distribution--monetization)); the Store
> build uses Store auto-update. Sections below that describe the Clips Manager, upload, or SQLite
> catalog are retained for history but are **not being built**.

---

## 1. Confirmed Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Distribution | winget / direct MSIX first, Microsoft Store soon after | Faster iteration; Store adds IAP + auto-update later |
| Minimum OS | **Windows 11 22H2 (build 22621+)** | Reliable `Windows.Graphics.Capture`: border control, cursor toggle, window exclusion, dirty-region; Mica/Acrylic |
| Architectures | **x64 + ARM64** (both v1) | Store users on ARM64; pure-managed GIF keeps this clean |
| Repo layout | Same repo, new top-level `/windows` folder | Shared history; macOS app untouched |
| Scope | Full parity, phased (capture core → editors/settings). **Clips Manager & upload removed from scope.** | Ship value early, de-risk the hard pipeline first |
| Language/stack | C# + WinUI 3 (Windows App SDK), **packaged MSIX with identity** | Identity unlocks toasts, StartupTask, Store add-ons |
| MVVM | CommunityToolkit.Mvvm + `Microsoft.Extensions.DependencyInjection` | Mirrors mac `ObservableObject`/`@Published` |
| Tooling | **Windows App Development CLI (`winapp`)** for SDK restore, identity, manifest, certs, signing, MSIX pack | Single toolchain across CI/local |
| Updater | **No Velopack.** Store build = Store updates; **Direct build = winget** (`winget upgrade`, publishing each release's signed MSIX to winget-pkgs) | MSIX already has identity/update semantics; winget is the single Direct channel |
| Pro / IAP | **Store build = `StoreContext` add-ons. Direct build is fully FREE** (all features unlocked, no purchase) | Store IAP only works in Store; avoids a separate license system entirely |
| Signing | **Azure Trusted Signing** for direct MSIX (account **not yet set up — Phase 4 prerequisite**); stable publisher identity forever | Avoids cert-trust install friction; self-signed cert only for internal test until then |
| Accounts | Microsoft **Partner Center: available**. Azure Trusted Signing: **to be provisioned** before Direct GA | Partner Center owns Store identity + name reservation |
| ~~Upload provider~~ | **Removed from scope** — no in-app upload/sharing | Browse captures in File Explorer instead |

---

## 2. Technology Mapping (macOS → Windows)

| macOS / Apple tech | Windows / WinUI 3 equivalent | Notes |
|---|---|---|
| SwiftUI `MenuBarExtra` | `H.NotifyIcon.WinUI` `TaskbarIcon` + flyout/menu | De-facto tray standard for WinUI 3 |
| `NSApplication` accessory (no Dock) | Packaged app, tray-only, no main window on launch; hidden bootstrap dispatcher | Single-instance via `AppInstance` |
| ScreenCaptureKit `SCStream`/`SCScreenshotManager` | **Windows.Graphics.Capture** (`Direct3D11CaptureFramePool`, `GraphicsCaptureItem`) | Per-monitor & per-window; region = crop |
| Region selection overlay (NSWindow) | One borderless topmost overlay window **per monitor** + frame crop | Sized in physical pixels; DIP for XAML |
| `AVAssetWriter` → MP4 (H.264) | **Media Foundation** `IMFSinkWriter` + `IMFDXGIDeviceManager` | NV12 input, HW encoder + SW fallback |
| `CGImageDestination` PNG/JPEG | `Windows.Graphics.Imaging` `BitmapEncoder` | Native PNG/JPEG, scale/quality |
| Animated GIF | **Dedicated pure-managed pipeline** (octree/median-cut quantize) | See §5.4; avoids native servicing on ARM64 |
| Microphone | `Windows.Media.Capture` / WASAPI capture | Muxed via MF audio sink |
| System audio loopback | **WASAPI loopback** (separate pipeline — WGC is video-only) | Audio clock can be master |
| Carbon `RegisterEventHotKey` | Win32 `RegisterHotKey` with conflict detection | Registration service w/ failure UI |
| Sparkle | Store auto-update (Store) / **winget** (Direct) | No Velopack |
| StoreKit 2 IAP | Microsoft Store add-ons via `StoreContext` (Store build only) | Direct build is fully free — no IAP/license |
| `@AppStorage` (UserDefaults) | `ApplicationData.LocalSettings` (prefs) | No SQLite catalog (Clips Manager removed) |
| `UserNotifications` | `AppNotificationManager` toasts | Requires identity (have it) |
| Launch at login | Packaged **`StartupTask`** (no registry for Store) | User-visible state + OS-denied fallback |
| Finder reveal / clipboard | Explorer `/select,`; `Clipboard` `DataPackage` | Save file before clipboard copy |
| Mica/vibrancy | `SystemBackdrop` Mica/Acrylic + Fluent theme | Light/Dark/System + High Contrast |

---

## 3. Feasibility Analysis — What We Can / Can't Support

### Fully supported (high confidence)
Screenshot (PNG/JPEG, scale/quality); video MP4/H.264 (fps + time limit); GIF; tray app + theming;
global hotkeys; countdown; region indicator; processing indicator; full settings parity; editors/trimmers;
mouse-click + branding overlays; onboarding + guide; toasts; clipboard;
reveal in Explorer; launch at login; MSIX/winget/Store; auto-update.

### Supported with caveats (designed-for in this plan)
- **Region capture** = capture monitor then crop each frame (GPU crop). Multi-monitor + per-monitor DPI handled via canonical coordinate model (§5.2).
- **System audio** = separate WASAPI loopback pipeline (WGC does **not** provide audio).
- **HDR monitors** = detect `R16G16B16A16Float` surfaces and tonemap to SDR BGRA8 before encode/GIF/PNG.
- **Mouse-click + branding overlays** = composited on the CPU into each BGRA frame before encode
  (implemented; the branding badge is rasterized once with GDI+ and alpha-blended per frame).
- **Self-window exclusion** = WGC exclusion API (22621+) with hide-windows + drop-pre-roll fallback.

### Not supported / platform-different (documented for users)
- **Game / exclusive-fullscreen capture is OUT for v1** (anti-cheat, protected swap chains). Documented limitation.
- **DRM/protected/elevated/secure-desktop surfaces** may black-frame → detect and show actionable errors.
- No "menu bar" concept → system tray UX (left-click flyout).
- macOS sandbox/entitlements → MSIX capabilities (minimal set, §7).

---

## 4. Architecture

```
/windows
  TinyClips.Windows.sln
  src/
    TinyClips.App/            # WinUI 3 packaged app: tray, windows, DI bootstrap, lifecycle
    TinyClips.Core/           # No-UI domain
      Capture/                # WGC source, frame processor, MF encoder/muxer, GIF pipeline, overlays
      Audio/                  # WASAPI loopback + mic, SessionClock
      Services/               # Settings, Storage, Permissions, HotKeys, Notifications, Update, Entitlement
      Catalog/                # SQLite clip catalog + migrations
      Models/                 # CaptureSettings, CaptureType, CaptureRegion, HotKeyBinding
    TinyClips.App.Tests/      # xUnit + golden-frame + media-validation harness
  packaging/
    msix/                     # Package.appxmanifest, assets, .appinstaller, winapp config
    winget/                   # winget manifest templates
  build/                      # winapp CLI scripts, CI tiers
plans/
  windows-winui3-port-plan.md # this document
```

### 4.1 Capture pipeline — discrete stages (decoupled from day 0)

```
CaptureSource (WGC, D3D11)
      │  Direct3D11CaptureFrame (+ SystemRelativeTime)
      ▼
FrameProcessor (GPU): crop → HDR tonemap → overlay composite (clicks/branding) → NV12 convert
      │
      ├──────────────► Encoder/Muxer (Media Foundation IMFSinkWriter, IMFDXGIDeviceManager)
      ▲                         ▲
AudioSource (WASAPI loopback + mic) ── audio samples ──┘
      │
SessionClock  ◄── master = WASAPI clock when audio on, else QPC/SystemRelativeTime monotonic
      │
SessionStateMachine  ── device-loss / monitor-change / encoder-failure / disk-full / revocation recovery
      │
StorageService (atomic temp-in-destination + rename, post-finalize) → SQLite catalog
      │
UI Coordinator (DispatcherQueue) ── tray, panels, indicators, progress
```

Design rules baked in from the review:
- **`SessionClock` abstraction exists even when audio is disabled**; switching audio on/off never changes the muxer.
- **NV12 is the assumed encoder input** (HW H.264 MFTs typically reject BGRA); GPU color-convert in `FrameProcessor`.
- **Threading/COM:** XAML/tray/flyouts on `DispatcherQueue` only; capture + encode on worker threads; bounded
  channels with backpressure/drop; explicit COM apartment + init model; **no blocking waits on `DispatcherQueue`**.
- **CaptureCoordinator is thin** — orchestration only; no god object (logic lives in the stages above).

### 4.2 Build configurations
Two MSBuild configs gate channel behavior via `DIRECT` / `STORE` constants (parallel to the mac `APPSTORE`):
- **Direct:** **winget** update path (`winget upgrade`); **all Pro features unlocked for free** (`FreeEntitlementService`); no Store APIs, no purchase/license UI.
- **Store:** Store auto-update, `StoreEntitlementService` add-ons, **no reachable self-update / appinstaller / winget / external-purchase UI** (Store-cert requirement).
- **Development:** `DevelopmentEntitlementService` (all features on, for local/dev).

All three implement a single channel-neutral **`IEntitlementService`** (identical feature flags, cache semantics, failure states) so feature-gating never leaks channel-specific APIs into ViewModels. The Direct build's `FreeEntitlementService` simply reports every feature as entitled.

---

## 5. Hardened Design Notes (from the review debate)

### 5.1 Media Foundation encoder (prototype FIRST, Phase 0 spike)
Validate the **real** path, not a toy: D3D11 texture input + `IMFDXGIDeviceManager`; BGRA/scRGB → **NV12** GPU
conversion (BT.709 matrix, color range, SDR metadata); HW encoder availability + SW fallback; AAC mux with
synthetic silence; H.264 profile/level/bitrate/GOP; **100 ns timestamp units**; PTS from frame `SystemRelativeTime`
with explicit pace/drop/duplicate policy for requested fps (never frame-index × interval).

> **Phase-0 spike outcome (`windows/spikes/MediaFoundationEncoderSpike`):** HW-accelerated H.264 + AAC →
> valid, ffprobe-verified MP4 confirmed end-to-end. The spike proved the **high-level WinRT path**
> (`MediaTranscoder` + `MediaStreamSource`, BGRA in → internal NV12, `HardwareAccelerationEnabled=true`) is by
> far the simplest viable encoder and is the recommended **default**. **Caveat / still to validate:**
> `MediaTranscoder` is a single-shot/finite transcode primitive — for an **unbounded recorder with pause/resume**
> we must validate a live, open-ended `MediaStreamSource` (signal-stop semantics) and keep **`IMFSinkWriter` +
> `IMFDXGIDeviceManager` (zero-copy D3D11/NV12) as the fallback** if the live transcoder path stalls or can't
> pause. Vortice's MediaFoundation surface was too incomplete; use WinRT or raw P/Invoke, not Vortice, for the encoder.

### 5.2 Coordinate / DPI model
Canonical space = **capture-frame pixels**. One borderless topmost overlay **per monitor**, sized in physical
pixels, rendered in DIPs. Conversions via `GetDpiForMonitor` / `MonitorFromPoint` / virtual-screen bounds.
Handle monitor **hotplug mid-selection**, negative-X virtual coords, portrait monitors, mixed 100%/150% scaling.
**Golden-frame crop tests** at 100% / 150% / negative-X / portrait.

### 5.3 Region overlay semantics
Toolwindow / no-taskbar; non-activating; Escape/cancel; **keyboard-only selection** path; current virtual desktop
only; topology-change-mid-drag handling; touch/pen input. High Contrast strokes/handles via system colors.

### 5.4 GIF pipeline (dedicated, pure-managed)
Downscale + fps-limit → octree/median-cut quantize (global vs per-frame palette decision) → optional
error-diffusion dither → frame differencing + disposal optimization. **Pure-managed** to keep x64+ARM64 clean and
avoid native CVE servicing; documented fallback if a native option is ever reconsidered.

### 5.5 Self-exclusion state machine
`capture preparing` → hide/close all capturable app surfaces (tray flyout, countdown, indicators, cursor overlay)
→ wait compositor idle + N captured frames → **drop pre-roll frames** → official record start. Golden-frame validated.
Recording status shown via **tray icon state + an excluded-from-capture floating indicator**; screenshots show no indicator.

### 5.6 Finalization & recovery
Muxer finalization outcomes: normal finalize / **recoverable partial finalize** / corrupt cleanup /
"saved up to failure" UI. **Atomic rename only after finalize success.** Device-loss state machine recovers from
device-removed, frame-pool recreate, monitor change, encoder failure, disk full, permission revocation
(display sleep, GPU reset, unplug, HDR toggle, RDP attach/detach).

### 5.7 Clip catalog (SQLite)
Per clip: stable clip ID, original path + current path, size/hash fingerprint, created/modified timestamps,
**missing-file state**, schema version. DB is **not** assumed source of truth when files are edited externally
(OneDrive sync, rename, external delete, duplicate names). Schema versioning + migrations from day 0.

### 5.8 Upload — REMOVED FROM SCOPE
~~Provider = Uploadcare; opt-in upload states; secure token storage.~~ The Windows app ships **no
in-app upload/sharing**. Users share captures from File Explorer. (Retained header for history.)

### 5.9 Trim policy (v1 = re-encode)
Trim creates a **new clip**, preserves original, warns on repeated
re-encode quality loss. Precise trim through the same MF encoder (no keyframe-only fast path in v1). Prototype cost.

### 5.10 Permission / onboarding state model
States: unknown / prompting / granted / denied / revoked / unsupported. Hotkeys and tray commands **route through
this state**, not directly into capture start.

### 5.11 App lifecycle
Single-instance via `AppInstance`; hidden bootstrap dispatcher; tray disposal on exit; explicit quit; activation
from toast / startup / protocol; survive Explorer restart (re-add tray icon).

---

## 6. Phased Delivery

### Phase 0 — Foundations, Tooling & SPIKES
- Install `winapp` CLI (`winget install Microsoft.winappcli`), Windows App SDK, VS; validate.
- Scaffold `/windows` solution (App / Core / Tests); DI + CommunityToolkit.Mvvm; settings service; Mica theming (Light/Dark/System/HC).
- Tray-only boot via `H.NotifyIcon`; **single-instance + lifecycle**.
- **Spikes (de-risk before UI):**
  1. **MF encoder** — D3D11/NV12/`IMFDXGIDeviceManager`/HW+SW/AAC-silence (§5.1).
  2. **WGC self-exclusion** + hide-windows fallback (§5.5).
  3. **Region overlay** multi-monitor / DPI / golden-frame crop (§5.2–5.3).
  4. **WGC capability matrix** — compile-time SDK target + runtime `ApiInformation` + per-capability fallback + packaged-vs-unpackaged behavior.

> **Phase-0 spike outcome (`windows/spikes/ScreenCaptureSpike`):** Monitor enumeration (physical-pixel bounds,
> negative-X secondary, per-monitor `GetDpiForMonitor`), runtime capability probing, and D3D11↔WGC interop
> (`CreateDirect3D11DeviceFromDXGIDevice` via Vortice.Direct3D11) all validated. Capability probing pattern works
> and must be **runtime per-capability** (`IsCursorCaptureEnabled`/`IsBorderRequired` present; `DirtyRegionMode`
> 22H2+, `TryExcludeWindowAsync` 24H2+ → use hide-windows + `SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)` +
> drop-pre-roll fallback). Region crop implemented via staging-texture `CopyResource` + `Map`, honoring **`RowPitch`**
> (not width×4). Frame timing model = monotonic `frame.SystemRelativeTime` as PTS. **Still to validate on an
> interactive desktop:** live `CreateForMonitor` capture (headless agent could not exercise DWM — `CreateForMonitor`
> threw "invalid cast", attributed to no compositor; must re-run on a real session before Phase 1 capture work).
- **Early dummy Store submission rehearsal** (Partner Center validation, restricted-capability review, privacy policy, age rating, **durable add-on product IDs**, sandbox purchase/restore, offline entitlement cache, no-op Pro gates).
- CI tiers: build/test/package on CI; **WACK in CI early**.

### Phase 1 — Capture Core (parity MVP)
Pipeline stages wired; region overlay + crop; screenshot (PNG/JPEG, scale, quality); video MP4 with
**audio-ready muxer** (audio disabled but `SessionClock` present); GIF pipeline; tray menu + hotkeys + countdown +
indicators + start/stop panels; **atomic save** + toasts + launch-at-login; permission state model;
**device-loss state machine**.

### Phase 2 — Editors & Full Settings + Audio
Screenshot editor; video trimmer (re-encode, new-clip policy); GIF trimmer; full settings UI (General, Video, GIF,
Mouse Clicks, Screenshot, Hotkeys); mouse-click + branding overlays in pipeline; **mic + system (WASAPI
loopback) audio enabled with AV sync** against master clock; HDR tonemap path validated on real HDR hardware.

### Phase 3 — Onboarding & Guide
Onboarding wizard + Guide window. *(Clips Manager & upload/sharing were removed from scope.)*

### Phase 4 — Distribution & Monetization
- **Direct (ships first):** signed MSIX published to **winget** (manifest + CI publish); users update with
  `winget upgrade`. Test upgrade/downgrade/reinstall from the winget origin; **update ownership per origin**.
  Direct build is **fully free** (no Pro gating, no purchase UI).
  - **Prerequisite:** provision **Azure Trusted Signing** before GA. Until then, use a self-signed cert for
    internal/sideload testing only (not public distribution).
- **Store (soon after):** Partner Center listing; Store add-ons for Pro; Store auto-update; Pro gating via
  `IEntitlementService`; **Store build ships no reachable self-update / winget / external-purchase UI**
  (cert requirement).
- Identity matrix frozen per channel (package name, publisher, cert subject, PFN, AUMID, notification identity, upgrade path).

### Phase 5 — Polish, A11y, Docs
Accessibility hardening (Narrator on all custom surfaces, keyboard-only region selection, visible focus, High
Contrast); DPI/coordinate + limitations docs (Windows analogue of `retina-display-capture.md`);
README/CONTRIBUTING/CHANGELOG + Windows build & packaging docs.

> Accessibility, theming (incl. High Contrast), and capability-minimalism are **acceptance criteria in every phase**, not just Phase 5.

---

## 7. Packaging, Identity & Distribution

- **`winapp` CLI:** `init`/`restore` (pin Windows App SDK + Windows SDK), `manifest generate`/`update-assets`,
  `cert generate`/`install` + `sign`, `pack` (MSIX, Store-ready), `create-debug-identity` (local toasts/StartupTask).
- **Capabilities (minimal):** `microphone` only when mic recording enabled; **no `broadFileSystemAccess`**;
  pickers / known folders where possible; disclose screen + audio capture and uploads; privacy policy required.
- **Identity matrix** defined and **frozen pre-release** per channel; never change publisher identity after release.
- **Direct:** Azure Trusted Signing; `.appinstaller` for auto-update; immutable signed release assets; documented cert rotation.
- **winget:** version manifest references the defined artifact; CI-automated; test `install`/`upgrade`/`uninstall`.
- **Store:** reserve name, upload MSIX (x64 + ARM64), configure add-ons, submit; Store owns updates; no self-update UI.

---

## 8. Testing Strategy
- **Unit:** xUnit for services, settings, catalog migrations, entitlement logic.
- **Golden-frame:** crop math at 100%/150%/negative-X/portrait.
- **Media validation:** duration vs wall clock, monotonic A/V timestamps, frame count tolerance, exact
  resolution/crop, **audio drift at 5/15/60 min**; playback in WMP/Photos/Edge/PowerPoint/Teams.
- **Soak:** long-run recordings; memory ceiling; thermals/perf budgets (1080p30, 1440p60, 4K30, multi-monitor).
- **CI tiers:** build/test/package + **WACK**; separate signed-package validation; manual hardware pass; Store validation pass.
- **Manual hardware matrix:** mixed-DPI, HDR + SDR mixed, RDP, DisplayLink/virtual displays, hybrid GPU,
  sleep/resume, lid close, monitor detach, **ARM64 device**.
- **Distribution rehearsal:** early dummy Store submission; `winget` + `.appinstaller` upgrade/downgrade/reinstall.

---

## 9. Risks & Open Items (tracked, non-blocking)
- Region-crop + overlay-composite + encode performance at high fps/DPI (perf budgets + GPU crop, bounded queues).
- WASAPI loopback reliability across devices and on ARM64.
- HDR tonemap quality tuning on real HDR panels.
- **Azure Trusted Signing not yet provisioned** — required before Direct GA (Phase 4 prerequisite).

**Resolved (human clarifications, 2026-06-12):**
- Pro is **Store-only**; Direct build is **fully free** → no license-key system needed.
- ~~Upload provider = Uploadcare~~ → **upload/sharing removed from scope** (browse in File Explorer).
- **Partner Center account available**; launch order kept **Direct first, Store soon after**.

## 10. Out of Scope (v1)
Game / exclusive-fullscreen capture; cross-device settings sync; non-Windows-11 support; keyframe-only fast trim.

---

## Appendix A — Review History
This plan was stress-tested in three adversarial review rounds with a second model (GPT-5.5) acting as critic:

- **Round 1 (40 items):** capture-pipeline correctness (DPI, multi-monitor, HDR, frame timing/VSync), AV sync,
  GIF quantization, MF encoder specifics, region overlay, performance/thermals, security/Store certification (WACK),
  packaging/identity/signing, updater strategy, IAP-only-in-Store, MVVM/threading, testing. **All accepted/folded in.**
- **Round 2 (17 second-order items):** `SessionClock` abstraction, NV12/D3D11 encoder reality, `IEntitlementService`
  separation, direct-update ownership, WGC capability matrix, overlay z-order/input, exclusion timing, muxer
  finalization, SQLite file identity, upload state/security, trim generation, GIF native risk, StartupTask per
  channel, early Store add-on rehearsal, permission state model, ARM64 decision, indicator policy. **All folded in.**
- **Round 3 (convergence):** one remaining Store-cert item — Store build must have **no reachable self-update /
  appinstaller / winget / external-purchase UI** (now in §4.2 / Phase 4). Critic declared remaining work
  **diminishing returns**. Plan converged.
