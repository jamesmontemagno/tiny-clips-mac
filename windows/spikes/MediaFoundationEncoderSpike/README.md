# Media Foundation H.264/MP4 Encoder Spike

A throwaway prototype to validate Windows Media Foundation H.264/MP4 encoding with hardware acceleration before building the production TinyClips Windows encoder.

## Purpose

This spike proves:
1. ✅ Hardware-accelerated H.264 encoding works on Windows
2. ✅ BGRA input format (from screen capture) is supported
3. ✅ AAC audio can be muxed into the output MP4
4. ✅ The encoding pipeline produces valid, playable files

## Requirements

- Windows 11 (or Windows 10 21H2+)
- .NET 10 SDK
- GPU with hardware H.264 encoder (Intel QSV, NVIDIA NVENC, or AMD VCE)
  - Falls back to software encoding if no hardware encoder available

## Building

```powershell
cd windows\spikes\MediaFoundationEncoderSpike
dotnet build MediaFoundationEncoderSpike.csproj -c Debug -p:Platform=x64
```

## Running

```powershell
cd windows\spikes\MediaFoundationEncoderSpike
dotnet run --project MediaFoundationEncoderSpike.csproj -c Debug -p:Platform=x64
```

Expected output:
```
=== Media Foundation H.264/MP4 Encoder Spike (WinRT) ===

Using Windows.Media APIs for encoding...
Creating video file...
Profile: H.264 1280x720 @ 30fps, AAC 48kHz stereo

Encoding video...
Hardware acceleration: True
  Encoded 30/90 frames...
  Encoded 60/90 frames...
  Encoded 90/90 frames...
✓ Encoding complete

=== VALIDATION ===
File size: 3,004,752 bytes (2934.33 KB)
✓ File has reasonable size for video content
✓ MP4 file created successfully

To verify playback, open the file in Windows Media Player or another video player.

=== SPIKE COMPLETE ===
Output file: G:\...\output.mp4
```

## Output

The spike generates `output.mp4` in the project directory:
- **Video:** H.264, 1280x720, 30fps, 8 Mbps, 3 seconds
- **Audio:** AAC, 48kHz stereo, 192 kbps, 3 seconds (silent)
- **Animation:** Moving orange/yellow rectangle on animated gradient background

## Verification

Play the output file in any video player, or use ffprobe:

```powershell
ffprobe -v error -show_format -show_streams output.mp4
```

Expected:
- Video codec: h264
- Audio codec: aac
- Duration: ~3.0 seconds
- Resolution: 1280x720

## Implementation Notes

- **Technology:** Windows.Media WinRT APIs (built into Windows, no external dependencies)
- **Hardware Acceleration:** Enabled via `MediaTranscoder.HardwareAccelerationEnabled = true`
- **Frame Generation:** Synthetic BGRA8 frames via `MediaStreamSource`
- **Color Conversion:** Automatic (BGRA → NV12 handled internally by Windows)
- **Audio:** Silent PCM → AAC automatic conversion

## Key Files

- `Program.cs` - Main implementation (~200 lines)
- `FINDINGS.md` - Detailed findings, gotchas, and production recommendations
- `output.mp4` - Generated output (git-ignored)

## Findings Summary

See [FINDINGS.md](FINDINGS.md) for complete analysis. Key points:

✅ **Hardware acceleration works** - GPU encoding confirmed  
✅ **BGRA input supported** - No manual color conversion required  
✅ **AAC audio muxing works** - Audio + video in single MP4  
✅ **Windows.Media APIs recommended** - Simpler than raw Media Foundation  

## Production Recommendation

Use `Windows.Media.Transcoding.MediaTranscoder` + `Windows.Media.Core.MediaStreamSource` for the production encoder:

**Pros:**
- Simple, high-level API
- Hardware acceleration automatic
- Built into Windows (no dependencies)
- Handles BGRA → NV12 conversion internally
- Audio+video muxing trivial

**Cons:**
- Less low-level control than native Media Foundation
- Event-driven model (not simple push-frames loop)

For most use cases (including TinyClips), the simplicity far outweighs the cons.

## NOT Part of Main Solution

This spike is intentionally **NOT** added to `windows\TinyClips.Windows.slnx`. It's a standalone, throwaway prototype for validation purposes only. Production code will integrate the findings but won't reuse this spike directly.
