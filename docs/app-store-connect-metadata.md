# TinyClips — App Store Connect Submission Info

Use this file as the source of truth when filling App Store Connect for the Mac App Store build (`TinyClipsMAS`).

## App Identity

- **App Name:** TinyClips
- **Bundle ID:** `com.refractored.tinyclips`
- **Platform:** macOS
- **Primary Category:** Developer Tools
- **Secondary Category:** Productivity (optional)

## Versioning

- **Version:** `0.0.9` (or next release version)
- **Build Number:** increment each upload (`CURRENT_PROJECT_VERSION`)
- **What’s New (Example):**
  - Added Mac App Store compatibility with sandbox-safe save locations.
  - Improved recording workflows and stability.
  - Fixed multiple build warnings and compatibility issues on macOS 15.

## Localized Metadata (en-US)

### Subtitle
Screenshots and video capture

### Promotional Text
Capture any part of your screen in seconds. Save screenshots, videos, or GIFs with optional trimming and editing.

### Description
TinyClips is a lightweight menu bar screen capture tool for macOS.

Capture exactly what you need:
- Screenshots of custom regions
- Screen recordings as video
- Short captures as GIFs

Built for speed and focus:
- Always available from the menu bar
- Quick keyboard shortcuts for all capture modes
- Optional countdown before recording
- Optional post-capture editing/trimming
- Clipboard copy and Finder reveal options

TinyClips is designed for developers, creators, and anyone who needs fast visual sharing without a complicated workflow.

### Keywords (100 chars max, comma-separated)
screenshot,screen recorder,gif,menu bar,capture,developer tools,productivity,screen capture,mac

## URLs

- **Support URL:** `https://github.com/jamesmontemagno/tiny-clips/issues`
- **Marketing URL:** `https://github.com/jamesmontemagno/tiny-clips`
- **Privacy Policy URL:**
  - Required for App Store submission.
  - Add a hosted privacy policy page and paste the final URL here.

## App Review Information

- **Contact First Name:** `James`
- **Contact Last Name:** `Montemagno`
- **Contact Email:** `your-support-email@example.com`
- **Contact Phone:** `your-phone-number`
- **Review Notes (recommended):**

```text
TinyClips is a menu bar utility (LSUIElement) with no Dock icon.

Core features:
1) Region screenshot capture
2) Region video recording
3) Region GIF recording

Permissions requested:
- Screen Recording: required to capture screen content.
- Microphone: only used when user enables microphone recording.

No account/login is required.
No in-app purchases.
```

## Content Rights & Compliance

### Export Compliance
- **Uses encryption:** Yes (standard Apple platform crypto / HTTPS)
- If prompted, select the standard exemption for apps using only exempt encryption.

### Content Rights
- Confirm you own or are licensed for all app assets (icon, screenshots, text).

### Advertising Identifier
- **IDFA used:** No

## Age Rating (suggested answers)

- **Unrestricted Web Access:** No
- **Gambling/Contests:** No
- **Medical/Treatment:** No
- **Mature/Sexual Content:** No
- **Violence/Horror:** No

Expected result: low age rating suitable for general productivity/developer utility.

## Privacy / App Privacy (Nutrition Labels)

Fill based on current app behavior:

- **Data Collection:** Typically `No` (if you do not collect personal data)
- **Tracking:** `No`
- **Diagnostics:** `No` unless you add analytics/crash reporting

If this changes, update App Privacy answers before submission.

## Entitlements & Capability Notes (MAS)

Current MAS entitlements include:
- App Sandbox
- Pictures read/write
- Movies read/write
- Audio input (microphone)
- User-selected file read/write
- App-scope bookmarks

These support capture output and user-selected save folders in sandbox mode.

## Screenshot & Media Checklist (Mac App Store)

Prepare these before submission:

- **macOS screenshots:** at least one, up to ten
- Show key flows:
  1. Menu bar capture menu
  2. Region selection overlay
  3. Screenshot result/editor
  4. Video recording flow (start/stop panel)
  5. GIF/trimmer flow
  6. Settings (General + capture options)

Optional but recommended:
- App preview video (if available)

## Pre-Submission QA Checklist

- [ ] Build and archive `TinyClipsMAS`
- [ ] Confirm sandboxed save works for defaults and custom folder bookmarks
- [ ] Confirm screenshot/video/GIF capture works on clean machine
- [ ] Confirm microphone toggle behavior and permission prompts
- [ ] Confirm no Sparkle UI/actions in MAS build
- [ ] Verify app name, subtitle, description, and keywords are final
- [ ] Upload final screenshots
- [ ] Add privacy policy URL
- [ ] Fill App Review contact details
- [ ] Submit for review

## Copy/Paste Block for App Store Connect

**Name:** TinyClips

**Subtitle:** Screenshots and video capture

**Promotional Text:** Capture any part of your screen in seconds. Save screenshots, videos, or GIFs with optional trimming and editing.

**Description:**
TinyClips is a lightweight menu bar screen capture tool for macOS.

Capture exactly what you need:
- Screenshots of custom regions
- Screen recordings as video
- Short captures as GIFs

Built for speed and focus:
- Always available from the menu bar
- Quick keyboard shortcuts for all capture modes
- Optional countdown before recording
- Optional post-capture editing/trimming
- Clipboard copy and Finder reveal options

TinyClips is designed for developers, creators, and anyone who needs fast visual sharing without a complicated workflow.

**Keywords:** screenshot,screen recorder,gif,menu bar,capture,developer tools,productivity,screen capture,mac

**Support URL:** https://github.com/jamesmontemagno/tiny-clips/issues

**Marketing URL:** https://github.com/jamesmontemagno/tiny-clips
