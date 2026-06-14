using System.Runtime.InteropServices;
using Vortice.Direct3D11;
using Vortice.DXGI;
using Windows.Graphics.Capture;
using Windows.Graphics.DirectX;
using Windows.Graphics.DirectX.Direct3D11;

namespace TinyClips.Core.Capture;

/// <summary>
/// Single-frame screen capture via Windows.Graphics.Capture (WGC) + Direct3D 11.
/// Targets a monitor by HMONITOR, grabs a settled frame, copies it to a CPU-readable
/// staging texture and returns tightly-packed BGRA8 pixels (optionally cropped).
/// </summary>
public sealed partial class ScreenCaptureService : IScreenCaptureService
{
    // Number of frames to observe before grabbing one, so the capture-start
    // transition / border flash isn't what we encode.
    private const int SettleFrames = 2;
    private const int CaptureTimeoutMs = 4000;

    public Task<CapturedFrame> CaptureMonitorAsync(
        nint hMonitor,
        PixelRect? region = null,
        bool includeCursor = false,
        CancellationToken cancellationToken = default)
        => CaptureAsync(CaptureTarget.Monitor(hMonitor), region, includeCursor, cancellationToken);

    public async Task<CapturedFrame> CaptureAsync(
        CaptureTarget target,
        PixelRect? region = null,
        bool includeCursor = false,
        CancellationToken cancellationToken = default)
    {
        if (!GraphicsCaptureSession.IsSupported())
        {
            throw new NotSupportedException("Windows.Graphics.Capture is not supported on this device.");
        }

        ID3D11Device? d3dDevice = null;
        IDirect3DDevice? device = null;
        Direct3D11CaptureFramePool? framePool = null;
        GraphicsCaptureSession? session = null;
        ID3D11Texture2D? stagingTexture = null;

        try
        {
            d3dDevice = WgcInterop.CreateD3D11Device()
                ?? throw new InvalidOperationException("Failed to create a Direct3D 11 device.");
            device = WgcInterop.CreateDirect3DDevice(d3dDevice)
                ?? throw new InvalidOperationException("Failed to create the WinRT IDirect3DDevice.");

            var item = target.CreateItem()
                ?? throw new InvalidOperationException("Failed to create a GraphicsCaptureItem for the target.");

            var size = item.Size;
            framePool = Direct3D11CaptureFramePool.CreateFreeThreaded(
                device,
                DirectXPixelFormat.B8G8R8A8UIntNormalized,
                2,
                size);

            session = framePool.CreateCaptureSession(item);
            WgcInterop.TryConfigureSession(session, includeCursor);

            var tcs = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
            var context = d3dDevice.ImmediateContext;
            int frameCount = 0;
            int frameWidth = 0;
            int frameHeight = 0;
            var sync = new object();

            framePool.FrameArrived += (pool, _) =>
            {
                try
                {
                    using var frame = pool.TryGetNextFrame();
                    if (frame is null)
                    {
                        return;
                    }

                    lock (sync)
                    {
                        if (tcs.Task.IsCompleted)
                        {
                            return;
                        }

                        using var frameTexture = WgcInterop.GetTextureFromFrame(frame);

                        var desc = frameTexture.Description;
                        if (stagingTexture is null)
                        {
                            frameWidth = (int)desc.Width;
                            frameHeight = (int)desc.Height;
                            stagingTexture = d3dDevice.CreateTexture2D(new Texture2DDescription
                            {
                                Width = desc.Width,
                                Height = desc.Height,
                                MipLevels = 1,
                                ArraySize = 1,
                                Format = desc.Format,
                                SampleDescription = new SampleDescription(1, 0),
                                Usage = ResourceUsage.Staging,
                                BindFlags = BindFlags.None,
                                CPUAccessFlags = CpuAccessFlags.Read,
                                MiscFlags = ResourceOptionFlags.None,
                            });
                        }

                        context.CopyResource(stagingTexture, frameTexture);
                        frameCount++;

                        if (frameCount >= SettleFrames)
                        {
                            tcs.TrySetResult(true);
                        }
                    }
                }
                catch (Exception ex)
                {
                    tcs.TrySetException(ex);
                }
            };

            session.StartCapture();

            using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeoutCts.CancelAfter(CaptureTimeoutMs);
            using (timeoutCts.Token.Register(() =>
            {
                // On timeout, accept whatever frame we have already copied.
                lock (sync)
                {
                    if (frameCount > 0)
                    {
                        tcs.TrySetResult(true);
                    }
                    else
                    {
                        tcs.TrySetException(new TimeoutException("No frames were captured before the timeout elapsed."));
                    }
                }
            }))
            {
                await tcs.Task.ConfigureAwait(false);
            }

            lock (sync)
            {
                if (stagingTexture is null)
                {
                    throw new InvalidOperationException("Capture produced no frame.");
                }

                return ReadStagingTexture(context, stagingTexture, frameWidth, frameHeight, region);
            }
        }
        finally
        {
            session?.Dispose();
            framePool?.Dispose();
            stagingTexture?.Dispose();
            device?.Dispose();
            d3dDevice?.Dispose();
        }
    }

    private static unsafe CapturedFrame ReadStagingTexture(
        ID3D11DeviceContext context,
        ID3D11Texture2D stagingTexture,
        int frameWidth,
        int frameHeight,
        PixelRect? region)
    {
        int x = 0, y = 0, width = frameWidth, height = frameHeight;
        if (region is { } r)
        {
            x = Math.Clamp(r.X, 0, frameWidth);
            y = Math.Clamp(r.Y, 0, frameHeight);
            width = Math.Clamp(r.Width, 1, frameWidth - x);
            height = Math.Clamp(r.Height, 1, frameHeight - y);
        }

        var mapped = context.Map(stagingTexture, 0, MapMode.Read, Vortice.Direct3D11.MapFlags.None);
        try
        {
            var pixels = new byte[width * height * 4];
            var src = (byte*)mapped.DataPointer;
            int srcPitch = (int)mapped.RowPitch;

            for (int row = 0; row < height; row++)
            {
                int srcOffset = ((y + row) * srcPitch) + (x * 4);
                int dstOffset = row * width * 4;
                Marshal.Copy(new nint(src + srcOffset), pixels, dstOffset, width * 4);
            }

            return new CapturedFrame(pixels, width, height);
        }
        finally
        {
            context.Unmap(stagingTexture, 0);
        }
    }
}
