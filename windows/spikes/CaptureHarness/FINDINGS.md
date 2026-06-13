# Capture Harness — Live WGC Validation

**Date:** 2026-06-12
**Status:** ✅ Gating item RESOLVED — live `CreateForMonitor` works on an interactive desktop.

## What this is

A tiny console app that references `TinyClips.Core` and exercises the real
`MonitorService` + `ScreenCaptureService` against the primary monitor, then encodes
the frame to PNG. It runs in the interactive desktop session (DWM active), unlike the
headless agent environment where the original `ScreenCaptureSpike` could not validate
live capture.

Run it with:

```pwsh
cd windows/spikes/CaptureHarness
dotnet run -c Debug
```

## Result

```
Primary: \\.\DISPLAY1 1536x960 @ 1.00x (HMONITOR 0x70109)
Captured frame: 1920x1200, 9216000 bytes
Saved PNG: %TEMP%\tinyclips_harness.png (2526864 bytes)
SUCCESS
```

A pixel-perfect, full-resolution screenshot of the live desktop was produced (no
yellow capture border, cursor excluded).

## Key resolution: CsWinRT COM interop

The original spike's `CreateForMonitor` failed with **"Specified cast is not valid"**.
The root cause was **not** the headless environment — it was the classic
`[ComImport]` + `Marshal.GetTypedObjectForIUnknown` interop pattern, which is
incompatible with CsWinRT's ComWrappers-based runtime.

**Fix (per the Microsoft `winappCli` sample):** use source-generated COM interop:

- `[GeneratedComInterface]` partial interfaces for `IGraphicsCaptureItemInterop`
  and `IDirect3DDxgiInterfaceAccess` (with `[PreserveSig] int` methods).
- Obtain the activation factory via `WinRT.ActivationFactory.Get(...)`, then
  `Marshal.QueryInterface(factory.ThisPtr, ...)`.
- Wrap raw COM pointers with
  `ComInterfaceMarshaller<T>.ConvertToManaged((void*)ptr)`.
- Wrap returned WinRT objects with `WinRT.MarshalInspectable<T>.FromAbi(ptr)`.
- Reach the captured texture via
  `((IWinRTObject)frame.Surface).NativeObject.ThisPtr` → QI
  `IDirect3DDxgiInterfaceAccess` → `GetInterface(ID3D11Texture2D)`.

## Notes

- `GraphicsCaptureItem.Size` reports **physical** pixels (1920×1200), while a
  DPI-unaware `GetMonitorInfo` reports effective/scaled bounds (1536×960). The
  capture pipeline uses `item.Size`, so the screenshot is full physical resolution.
- Region crop honours `RowPitch` (stride may exceed `width * 4`).
- This harness is excluded from the solution and CI; it is a manual validation tool.
