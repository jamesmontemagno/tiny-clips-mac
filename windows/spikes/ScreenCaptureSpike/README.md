# ScreenCaptureSpike

**De-risking spike for Windows.Graphics.Capture (WGC) screen capture implementation**

## Purpose

Validate the Windows.Graphics.Capture API path for screen recording, including:
- Multi-monitor enumeration with DPI/scale detection
- Programmatic monitor capture (no picker UI)
- Frame timing model (`SystemRelativeTime` PTS)
- Region cropping (sub-rectangle from full frame)
- API capability detection (cursor toggle, border, dirty-region, window exclusion)
- Self-window exclusion strategies

## Project Structure

```
ScreenCaptureSpike/
├── ScreenCaptureSpike.csproj   # Standalone console app (net10.0-windows10.0.26100.0)
├── Program.cs                  # All spike logic
├── FINDINGS.md                 # Detailed results and recommendations
└── README.md                   # This file
```

## Requirements

- **OS**: Windows 11 22H2+ (Build 22621+)
- **SDK**: .NET 10 SDK, Windows SDK 10.0.26100.0+
- **Platform**: x64 or ARM64
- **Dependencies**: Vortice.Direct3D11 v3.8.1, Vortice.DXGI v3.8.1 (pure-managed D3D11 interop)

## Build and Run

```powershell
# Build
cd windows\spikes\ScreenCaptureSpike
dotnet build -c Debug -p:Platform=x64

# Run
dotnet run --project ScreenCaptureSpike.csproj -c Debug -p:Platform=x64
```

## What It Does

1. **Enumerate monitors**: P/Invoke to `user32!EnumDisplayMonitors` + `shcore!GetDpiForMonitor`
   - Reports device name, bounds (physical pixels), DPI, scale factor, primary flag, HMONITOR
   - Handles negative X coordinates (secondary monitors to the left)

2. **Probe API capabilities**: Uses `ApiInformation` to check for:
   - `IsCursorCaptureEnabled` (cursor toggle)
   - `IsBorderRequired` (yellow border toggle)
   - `GraphicsCaptureSessionDirtyRegionMode` (dirty-region optimization)
   - `TryExcludeWindowAsync` (window exclusion API)

3. **Capture test** (if interactive desktop):
   - Create D3D11 device + `IDirect3DDevice` for WGC
   - Create `GraphicsCaptureItem` via `IGraphicsCaptureItemInterop::CreateForMonitor`
   - Start `GraphicsCaptureSession` and capture ~30 frames
   - Measure `frame.SystemRelativeTime` cadence (verify monotonic, ~16ms delta @ 60Hz)

4. **Region crop test** (if frames captured):
   - Copy last frame to CPU-readable staging texture
   - Crop 400×300 region at offset (100, 100)
   - Save both full frame and cropped region as PNG
   - Verify cropped PNG dimensions exactly match

## Known Limitations

- **Headless/agent environments**: WGC requires Desktop Window Manager (DWM) and an active desktop session. Frame capture will fail in headless CI or remote sessions without GPU.
- **COM interop**: `IGraphicsCaptureItemInterop` activation factory interop may fail if DWM is not running. This is expected and does not indicate a code issue.

## Results

See **[FINDINGS.md](./FINDINGS.md)** for:
- Monitor enumeration results (validated ✅)
- API capability matrix (validated ✅)
- Frame timing expectations (implementation ready, needs interactive desktop)
- Region crop approach (implementation ready, needs interactive desktop)
- Production `CaptureSource` design recommendations

## Next Steps

1. **Run on interactive Windows desktop** with DWM active to validate live frame capture.
2. If `CreateForMonitor` interop still fails, try CsWinRT source generator.
3. Integrate validated patterns into production `CaptureSource` + `CaptureSession`.

## Notes

- This is a **throwaway prototype** — code quality is spike-level, not production-ready.
- Do NOT add this project to `windows\TinyClips.Windows.slnx`.
- Region crop uses CPU staging texture (sufficient for <120 FPS). For higher frame rates, consider GPU-based crop.
