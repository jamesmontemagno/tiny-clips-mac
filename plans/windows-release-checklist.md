# TinyClips for Windows — Release Checklist (Microsoft Store + winget)

> **Purpose:** a concrete, do-this-next runbook for shipping the Windows (WinUI 3) build to
> **winget / direct MSIX** (ships first) and the **Microsoft Store** (soon after). This is the
> "what's left" list — the strategy lives in `plans/windows-winui3-port-plan.md` and the
> how-to lives in `windows/packaging/README.md`.
>
> Legend: ☐ = to do · ⚠️ = needs an account/secret only the maintainer can provide · 🤖 = automatable in CI.

---

## 0. Where we are today (baseline)

| Thing | State |
| --- | --- |
| App packaging | Single-project **MSIX with identity** (`EnableMsixTooling`), `Refractored.TinyClips`, `Publisher=CN=Refractored`, version `1.0.0.0`. |
| Architectures | **x64 + ARM64** (`<Platforms>x64;ARM64</Platforms>`). |
| Min OS | `10.0.22621.0` (Win 11 22H2). |
| Capabilities | `runFullTrust` + `microphone` declared in `Package.appxmanifest`. |
| winget manifest | **Templates exist** in `windows/packaging/winget/` (installer/locale/version) with `<FILL-IN>` placeholders. |
| CI | `windows-build.yml` builds x64+ARM64 Release + runs Core tests on PR. **No release/packaging/signing CI.** `release.yml` is **macOS-only**. |
| Signing | **Not set up.** Azure Trusted Signing to be provisioned (Phase 4 prereq). |
| Store/Direct split | **Not implemented yet** — no `IEntitlementService` Free vs Store builds, no Store config, no add-ons. |
| WACK | Not run. |

---

## 1. Shared prerequisites (do once, both channels)

- ☐ **Freeze the identity matrix** (see §5). Confirm final **package family name (PFN)**, publisher,
  display name. Note: the **Store will assign its own Identity/Publisher** — the Direct build keeps
  `CN=Refractored` (or the Trusted Signing subject); the two channels are **different identities**.
- ☐ **Version strategy** — map release tag `vMAJOR.MINOR.PATCH` → `Package.appxmanifest`
  `Version="MAJOR.MINOR.PATCH.0"` (4-part, revision `0`). Bump on every submission (Store/winget
  reject duplicate versions). 🤖 stamp this in CI from the tag.
- ☐ **App assets audit** — confirm every tile/logo scale referenced in `Package.appxmanifest`
  exists and renders (Square44/150, Wide310x150, SmallTile, LargeTile, SplashScreen, StoreLogo).
  Verify the new macOS-matched icon is exported at all scales.
- ☐ **Privacy policy URL** — required by the Store, recommended for winget. Publish a page (repo
  `docs/` or GitHub Pages) covering: screen capture, microphone, system-audio, local file save,
  no telemetry (state plainly). Capture the URL for both submissions.
- ☐ **Release notes source** — reuse `windows/CHANGELOG.md` `## [Unreleased]` → cut a versioned
  `## [vX.Y.Z]` section per release; feed it to GitHub Release body, Store "what's new", and the
  winget locale `ReleaseNotes`.
- ☐ **WACK pass** — run the Windows App Certification Kit on the Release MSIX (x64 **and** ARM64):
  `& "${env:ProgramFiles(x86)}\Windows Kits\10\App Certification Kit\appcert.exe" test -appxpackagepath <msix> -reportoutputpath wack.xml`.
  Fix any failures **before** either submission. 🤖 add to CI.
- ☐ **Clean-machine smoke test** — install the **signed** MSIX on a machine without the dev cert and
  without VS; verify tray launch, screenshot/video/GIF capture, save to `Pictures\TinyClips`, toast,
  microphone/system-audio recording, and "launch at login" (StartupTask) all work under identity.
- ☐ **Decide Direct vs Store feature split now** (blocks the Store build): introduce
  `IEntitlementService` with `FreeEntitlementService` (Direct = all features free) and
  `StoreEntitlementService` (Store add-ons). The **Store build must ship no reachable self-update /
  `.appinstaller` / winget / external-purchase UI** (Store-cert requirement). Direct build has no
  Store APIs. Gate via build configuration / compilation symbol.

---

## 2. Channel A — Direct MSIX + winget (ships first)

### 2.1 Code signing (the gating item)  ⚠️
- ☐ **Provision Azure Trusted Signing** (recommended): Azure subscription → Trusted Signing account →
  certificate profile; validate the **publisher identity** (`CN=...`) — this becomes the permanent
  Direct identity. *Until provisioned, only self-signed certs work and winget will reject the
  submission (untrusted signature).*
- ☐ Make sure `Package.appxmanifest` `Publisher` **exactly matches** the signing cert subject, or
  packaging will fail signature validation.
- ☐ (Interim, internal test only) self-signed: `winapp cert generate --publisher "CN=Refractored"`
  + `winapp cert install`. Never publish a self-signed build to winget.

### 2.2 Build + sign the MSIX
- ☐ `winapp restore` (pin SDKs / projections).
- ☐ `dotnet publish src/TinyClips.App/TinyClips.App.csproj -c Release -p:Platform=x64` and `-p:Platform=arm64`.
- ☐ `winapp pack` (or `msbuild /t:GenerateAppxPackage`) → MSIX per arch (or a single `.msixbundle`).
- ☐ Sign with Trusted Signing (`winapp sign --package <.msix>` / the Trusted Signing task/action).
- ☐ Decide **single `.msixbundle` (x64+ARM64)** vs **two arch-specific MSIX**. winget supports both;
  bundle is simpler for one InstallerUrl, per-arch gives smaller downloads. **Recommend per-arch MSIX**
  (matches the existing installer manifest, which already lists two `Installers`).

### 2.3 (Optional) `.appinstaller` auto-update for Direct
- ☐ Generate an `.appinstaller` pointing at a stable URL (GitHub Pages / release asset) so Direct
  users get automatic updates without winget. Document the hosting URL and update cadence.
- ☐ Verify update ownership: a package installed via `.appinstaller` vs winget must upgrade cleanly
  (same identity/PFN); test cross-origin upgrade/downgrade/reinstall.

### 2.4 GitHub Release
- ☐ Tag `vX.Y.Z`; attach the **signed** MSIX/bundle assets (immutable — never replace a published asset).
- ☐ Body = the versioned CHANGELOG section. 🤖 via a new Windows release workflow (§4).

### 2.5 Fill + validate the winget manifest
The 3-file manifest lives in `windows/packaging/winget/`. Per release:
- ☐ `PackageVersion` → new version (must not already exist in winget-pkgs).
- ☐ Installer manifest per arch:
  - `InstallerUrl` → the GitHub Release asset URL.
  - `InstallerSha256` → `winget hash <path-to.msix>`.
  - `SignatureSha256` → `winget hash --msix <path-to.msix>` (required for msix).
  - `PackageFamilyName` → **real PFN** from the signed package:
    `Get-AppxPackage Refractored.TinyClips | Select-Object PackageFamilyName` (replace the
    `<publisher-id-hash>` placeholder).
  - `MinimumOSVersion` → `10.0.22621.0` (matches manifest).
- ☐ Locale manifest (`...locale.en-US.yaml`) is **already populated** (PackageName, Publisher,
  PublisherUrl/SupportUrl, Author, License MIT, Description, Moniker `tinyclips`, Tags). Optional
  adds per release: `Copyright` ("© <year> Refractored LLC") and `ReleaseNotes`/`ReleaseNotesUrl`.
  The version manifest (`...yaml`) is complete. **Only the installer manifest needs per-release
  edits** (URLs, hashes, real PFN).
- ☐ Validate: `winget validate --manifest windows/packaging/winget`.
- ☐ Local install test: `winget install --manifest windows/packaging/winget`; then
  `winget upgrade` and `winget uninstall` round-trip.

### 2.6 Submit to winget-pkgs
- ☐ PR to [microsoft/winget-pkgs](https://github.com/microsoft/winget-pkgs) **or** `wingetcreate submit`
  (uses a PAT). ⚠️ needs the maintainer's GitHub account. 🤖 automate `wingetcreate update` on tag.
- ☐ Respond to the winget bot's validation (manifest schema, signature match, installer reachability).

---

## 3. Channel B — Microsoft Store (soon after)

### 3.1 Partner Center setup  ⚠️
- ☐ Reserve the app name **Tiny Clips** in Partner Center (account is available per the port plan).
- ☐ Create the app; record the Store-assigned **Identity** (`Name`, `Publisher`,
  `PublisherDisplayName`) and **PFN** — these differ from the Direct identity.

### 3.2 Store-configured package
- ☐ Produce a **Store build** whose `Package.appxmanifest` `Identity`/`Publisher` are overridden with
  the Store values (Visual Studio "Associate App with the Store", or `winapp` pull, or a separate
  Store manifest/config). Do **not** ship the Direct `CN=Refractored` identity to the Store.
- ☐ Build the Store upload package: **`.msixupload`** bundling **x64 + ARM64** (Store re-signs).
- ☐ Ensure the **Store build flavor** uses `StoreEntitlementService` and hides all self-update /
  winget / `.appinstaller` / external-purchase UI (Store-cert requirement, §1).

### 3.3 Pro / in-app purchases (Store-only)
- ☐ Create **durable add-ons** (Pro: monthly / yearly / lifetime — mirror the macOS `ProPlan`) with
  **stable product IDs** in Partner Center.
- ☐ Wire `StoreContext` purchase + license check behind `IEntitlementService`; add an **offline
  entitlement cache** so Pro survives offline launches.
- ☐ Sandbox test **purchase + restore** for each product; verify no-op Pro gates when not purchased.
- ☐ Confirm **Direct build has no IAP/license code paths** (fully free).

### 3.4 Listing + compliance
- ☐ Store listing metadata: description, **screenshots** (capture from the running Windows app — the
  existing `docs/app-store-connect-metadata.md` is **macOS**; a Windows listing pack is needed),
  store logos, category (Photo & video / Productivity), search terms, **copyright © <year>
  Refractored LLC**.
- ☐ **Privacy policy URL** (required).
- ☐ **Age rating** (IARC questionnaire).
- ☐ **Capability justifications**: `runFullTrust` requires a "why full trust" justification in Partner
  Center (needed for WGC screen capture + WASAPI audio + arbitrary file save); `microphone` needs a
  usage justification. Prepare short rationales.
- ☐ Note: Windows Graphics Capture itself needs **no restricted capability**, but the full-trust
  justification above still applies.

### 3.5 Submit + certify
- ☐ Upload `.msixupload`, complete all sections, submit for certification.
- ☐ Address cert feedback; use **phased / staged rollout** for the first release.
- ☐ Confirm Store auto-update works and the Direct/Store identities don't collide on one machine.

---

## 4. CI / automation gaps to close  🤖

- ☐ **New `windows-release.yml`** (tag `v*` triggered), separate from the macOS `release.yml`:
  1. Build Release x64 + ARM64.
  2. `winapp pack` → MSIX/bundle.
  3. **Sign** via Azure Trusted Signing (GitHub action / `azuresigntool`) — needs Azure creds as
     repo secrets. ⚠️
  4. Run **WACK**; fail on errors.
  5. Compute `InstallerSha256` + `SignatureSha256`; stamp version from tag.
  6. Create GitHub Release with signed assets + CHANGELOG body.
  7. (Optional) `wingetcreate update` to open the winget-pkgs PR automatically. ⚠️ PAT secret.
- ☐ **Store publish** can be automated later via the Partner Center submission API / Store action
  (separate secrets); start manual.
- ☐ Add WACK + (optionally) signed-package validation as a CI tier.

---

## 5. Identity matrix (freeze before first release)

| Field | Direct (winget/MSIX) | Store |
| --- | --- | --- |
| Package Name | `Refractored.TinyClips` | **Store-assigned** |
| Publisher | `CN=Refractored` (or Trusted Signing subject) | **Store-assigned** (`CN=<GUID>`) |
| PublisherDisplayName | `Refractored` | Partner Center display name |
| Version | from tag → `X.Y.Z.0` | from tag → `X.Y.Z.0` |
| Signing | Azure Trusted Signing | Store re-signs |
| Updates | `.appinstaller` + winget | Store |
| Entitlement | `FreeEntitlementService` (all free) | `StoreEntitlementService` (add-ons) |
| Self-update/winget/purchase UI | allowed | **must be absent** |

> Once published, these are effectively permanent (changing PFN breaks upgrades). Lock them in.

---

## 6. Open decisions for the maintainer

1. **Signing**: provision **Azure Trusted Signing** (recommended, no cert-trust friction) vs buy an
   OV/EV cert? This gates the entire Direct/winget path.
2. **Direct package shape**: per-arch MSIX (matches current winget template) vs a single
   `.msixbundle`?
3. **`.appinstaller` auto-update for Direct**: ship it (and host where — GitHub Pages?) or rely on
   winget upgrades only for v1?
4. **Store timing**: cut Direct/winget v1 first, then do the Store entitlement split + add-ons as a
   follow-up — confirm this order (matches the plan's "Direct first, Store soon after").
5. **Pro on Windows**: confirm the same three add-ons as macOS (monthly/yearly/lifetime), or a
   different model for the Store build.
6. **Min OS**: keep `22621` (Win 11 22H2), or lower to a Win 10 build to widen reach?

---

## 7. Suggested order of execution

1. §1 shared prereqs (identity freeze, version stamping, assets, privacy policy, WACK dry-run).
2. **Direct/winget path** (§2) end-to-end with a **self-signed internal build** to prove pack →
   hash → manifest → `winget install` locally.
3. Provision **Trusted Signing** (§2.1) → re-sign → first **real** GitHub Release + winget PR.
4. Add **`windows-release.yml`** (§4) to automate steps 2–3.
5. **Store split** (§1 entitlement + §3): Partner Center, Store identity, add-ons, listing, submit.
