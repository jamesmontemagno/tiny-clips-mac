# TinyClips for Windows — Packaging & Distribution

This folder holds the artifacts for shipping TinyClips via **direct MSIX / winget** and the
**Microsoft Store**. The app is a packaged (MSIX, identity-bearing) WinUI 3 app, which is what
enables toast notifications, startup tasks, and Store distribution.

## Prerequisites

- Windows App Development CLI (`winapp`): `winget install Microsoft.winappcli`
- Windows App SDK + Windows SDK (restored by `winapp restore`)
- A code-signing certificate (dev: self-signed; release: trusted CA or Store-signed)

## 1. Build a signed MSIX (direct distribution)

```pwsh
# From repo root
cd windows

# Pin SDKs / generate projections
winapp restore

# (Dev only) create + trust a local signing cert
winapp cert generate --publisher "CN=Refractored"
winapp cert install

# Produce the MSIX (x64 and arm64)
dotnet publish src/TinyClips.App/TinyClips.App.csproj -c Release -p:Platform=x64
dotnet publish src/TinyClips.App/TinyClips.App.csproj -c Release -p:Platform=arm64
winapp pack   # or `msbuild /t:GenerateAppxPackage`

# Sign the package(s)
winapp sign --package <path-to.msix>
```

Attach the signed `.msix` files to a GitHub Release (e.g. `v1.0.0`).

## 2. Publish to winget

The three-file manifest in this folder (`*.yaml`) is the winget submission. After a signed
release exists:

1. Fill in the installer manifest:
   - `InstallerUrl` → the Release asset URL
   - `InstallerSha256` → `winget hash <path-to.msix>`
   - `SignatureSha256` → `winget hash --msix <path-to.msix>`
   - `PackageFamilyName` → from `Get-AppxPackage Refractored.TinyClips | Select PackageFamilyName`
2. Validate: `winget validate --manifest windows/packaging/winget`
3. Test locally: `winget install --manifest windows/packaging/winget`
4. Submit a PR to [microsoft/winget-pkgs](https://github.com/microsoft/winget-pkgs) (or use
   `wingetcreate submit`). This can be automated in CI on each tagged release.

The locale manifest already includes:
- `PrivacyUrl: https://tinyclips.app/privacy.html`

> ⚠️ Requires the maintainer's GitHub account; the signed MSIX + hashes can only be produced
> from a release build with the real signing certificate.

## 3. Microsoft Store

1. Reserve the app name **Tiny Clips** in Partner Center.
2. Associate the app identity (`winapp` can pull the Store identity to override the dev
   `Package.appxmanifest` `Identity`).
3. Build the Store-configuration MSIX (Store handles signing) and upload via Partner Center
   or `winapp` Store submission.
4. Build with the Store flavor flag so Store-only distribution behavior is enabled:
   `dotnet publish src/TinyClips.App/TinyClips.App.csproj -c Release -p:Platform=x64 -p:TinyClipsStoreBuild=true`
   (repeat for ARM64 as needed).
5. Complete the listing metadata, privacy, and screen-recording capability declarations.
   - Privacy policy URL: `https://tinyclips.app/privacy.html`

> ⚠️ Requires a Partner Center account; cannot be completed from the repo alone.

## Capabilities

The current feature set (Graphics.Capture, toast notifications, file save to
Pictures/Videos) runs under `runFullTrust` with package identity — no extra manifest
capabilities are required. The `microphone` device capability is already declared in
`Package.appxmanifest` to support audio recording.
