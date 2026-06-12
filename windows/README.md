# Tiny Clips for Windows

A native **WinUI 3 / Windows App SDK** port of Tiny Clips — a tray-based screen-capture app
(screenshots, video, GIF). See the full design in
[`/plans/windows-winui3-port-plan.md`](../plans/windows-winui3-port-plan.md).

> Status: **Phase 0 (foundations)** — tray-first app shell, DI, settings/entitlement services, CI.

## Requirements

- Windows 11 **22H2 (build 22621)** or later
- [.NET 10 SDK](https://dotnet.microsoft.com/)
- Windows SDK `10.0.26100`
- **Developer Mode** enabled (Settings → System → For developers) for MSIX sideload/registration
- Optional: [Windows App Development CLI (`winapp`)](https://learn.microsoft.com/windows/apps/dev-tools/winapp-cli/)
  for identity, manifest, signing, and MSIX packaging:
  ```powershell
  winget install Microsoft.winappcli --source winget
  ```

## Project layout

```
windows/
  TinyClips.Windows.slnx        Solution
  Directory.Build.props         Shared TFM / min-version / platforms (x64, ARM64)
  src/
    TinyClips.App/              WinUI 3 packaged app (tray, DI bootstrap, windows)
    TinyClips.Core/             UI-free domain (services, models) — capture pipeline lands here
  tests/
    TinyClips.Core.Tests/       xUnit tests
  packaging/
    msix/  winget/              Packaging artifacts (later phases)
  spikes/                       Throwaway de-risking prototypes (not in the solution/CI)
```

## Build & run

WinUI 3 requires an explicit platform (`x64` or `ARM64`; `AnyCPU` is not supported).

```powershell
# Restore
dotnet restore windows/TinyClips.Windows.slnx

# Build the app
dotnet build windows/src/TinyClips.App/TinyClips.App.csproj -c Debug -p:Platform=x64

# Run with package identity (uses the winapp CLI under the hood)
dotnet run --project windows/src/TinyClips.App/TinyClips.App.csproj -c Debug -p:Platform=x64

# Test
dotnet test windows/tests/TinyClips.Core.Tests/TinyClips.Core.Tests.csproj -c Debug
```

The app launches **tray-only** (no window). Right-click the tray icon for the menu;
**Settings** opens a placeholder window, **Exit** quits.

## CI

`.github/workflows/windows-build.yml` builds `x64` + `ARM64` and runs the Core tests on
`windows-latest`. It is path-filtered to `windows/**`, so it only runs when Windows code changes.

## Distribution (planned)

- **Direct:** signed MSIX + `.appinstaller` auto-update, plus a winget manifest. Fully free.
- **Microsoft Store:** Store auto-update + Pro add-ons (Pro is Store-only).

See the plan for the full phased roadmap, packaging, and signing details.
