namespace TinyClips.Core.Capture;

/// <summary>
/// A captured raster frame in tightly-packed BGRA8 (premultiplied) pixels,
/// i.e. row stride is exactly <see cref="Width"/> * 4 bytes.
/// </summary>
public sealed class CapturedFrame
{
    public CapturedFrame(byte[] bgraPixels, int width, int height)
    {
        BgraPixels = bgraPixels;
        Width = width;
        Height = height;
    }

    public byte[] BgraPixels { get; }

    public int Width { get; }

    public int Height { get; }
}
