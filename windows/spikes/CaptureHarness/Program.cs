using TinyClips.Core.Capture;

Console.WriteLine("=== TinyClips capture harness ===");

var monitors = new MonitorService();
var primary = monitors.GetPrimaryMonitor();
if (primary is null)
{
    Console.WriteLine("No monitor found.");
    return 1;
}

Console.WriteLine($"Primary: {primary.DeviceName} {primary.Width}x{primary.Height} @ {primary.ScaleFactor:F2}x (HMONITOR 0x{primary.HMonitor:X})");

var capture = new ScreenCaptureService();
try
{
    var frame = await capture.CaptureMonitorAsync(primary.HMonitor, includeCursor: false);
    Console.WriteLine($"Captured frame: {frame.Width}x{frame.Height}, {frame.BgraPixels.Length} bytes");

    var outPath = Path.Combine(Path.GetTempPath(), "tinyclips_harness.png");
    // Encode via the same WinRT path the app uses.
    using var stream = new Windows.Storage.Streams.InMemoryRandomAccessStream();
    var encoder = await Windows.Graphics.Imaging.BitmapEncoder.CreateAsync(
        Windows.Graphics.Imaging.BitmapEncoder.PngEncoderId, stream);
    encoder.SetPixelData(
        Windows.Graphics.Imaging.BitmapPixelFormat.Bgra8,
        Windows.Graphics.Imaging.BitmapAlphaMode.Premultiplied,
        (uint)frame.Width, (uint)frame.Height, 96, 96, frame.BgraPixels);
    await encoder.FlushAsync();
    stream.Seek(0);
    var size = (uint)stream.Size;
    using var reader = new Windows.Storage.Streams.DataReader(stream.GetInputStreamAt(0));
    await reader.LoadAsync(size);
    var bytes = new byte[size];
    reader.ReadBytes(bytes);
    await File.WriteAllBytesAsync(outPath, bytes);

    Console.WriteLine($"Saved PNG: {outPath} ({bytes.Length} bytes)");
    Console.WriteLine("SUCCESS");
    return 0;
}
catch (Exception ex)
{
    Console.WriteLine($"CAPTURE FAILED: {ex.GetType().Name}: {ex.Message}");
    Console.WriteLine(ex.StackTrace);
    return 2;
}
