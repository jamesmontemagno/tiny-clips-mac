using System.Runtime.InteropServices;
using System.Runtime.InteropServices.Marshalling;
using Vortice.Direct3D;
using Vortice.Direct3D11;
using Vortice.DXGI;
using Windows.Foundation.Metadata;
using Windows.Graphics.Capture;
using Windows.Graphics.DirectX;
using Windows.Graphics.DirectX.Direct3D11;
using WinRT;

namespace TinyClips.Core.Capture;

/// <summary>
/// Single-frame screen capture via Windows.Graphics.Capture (WGC) + Direct3D 11.
/// Targets a monitor by HMONITOR, grabs a settled frame, copies it to a CPU-readable
/// staging texture and returns tightly-packed BGRA8 pixels (optionally cropped).
/// </summary>
public sealed partial class ScreenCaptureService : IScreenCaptureService
{
    private static readonly Guid GraphicsCaptureItemGuid = new("79C3F95B-31F7-4EC2-A464-632EF5D30760");
    private static readonly Guid GraphicsCaptureItemInteropGuid = new("3628E81B-3CAC-4C60-B7F4-23CE0E0C3356");
    private static readonly Guid Direct3DDxgiInterfaceAccessGuid = new("A9B3D012-3DF2-4EE3-B8D1-8695F457D3C1");
    private static readonly Guid D3D11Texture2DGuid = new("6F15AAF2-D208-4E89-9AB4-489535D34F9C");

    // Number of frames to observe before grabbing one, so the capture-start
    // transition / border flash isn't what we encode.
    private const int SettleFrames = 2;
    private const int CaptureTimeoutMs = 4000;

    public async Task<CapturedFrame> CaptureMonitorAsync(
        nint hMonitor,
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
            d3dDevice = CreateD3D11Device()
                ?? throw new InvalidOperationException("Failed to create a Direct3D 11 device.");
            device = CreateDirect3DDevice(d3dDevice)
                ?? throw new InvalidOperationException("Failed to create the WinRT IDirect3DDevice.");

            var item = CreateCaptureItemForMonitor(hMonitor)
                ?? throw new InvalidOperationException("Failed to create a GraphicsCaptureItem for the monitor.");

            var size = item.Size;
            framePool = Direct3D11CaptureFramePool.CreateFreeThreaded(
                device,
                DirectXPixelFormat.B8G8R8A8UIntNormalized,
                2,
                size);

            session = framePool.CreateCaptureSession(item);
            TryConfigureSession(session, includeCursor);

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

                        using var frameTexture = GetTextureFromFrame(frame);

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

    private static void TryConfigureSession(GraphicsCaptureSession session, bool includeCursor)
    {
        try
        {
            if (ApiInformation.IsPropertyPresent("Windows.Graphics.Capture.GraphicsCaptureSession", "IsCursorCaptureEnabled"))
            {
                session.IsCursorCaptureEnabled = includeCursor;
            }

            if (ApiInformation.IsPropertyPresent("Windows.Graphics.Capture.GraphicsCaptureSession", "IsBorderRequired"))
            {
                session.IsBorderRequired = false;
            }
        }
        catch
        {
            // Capability toggles are best-effort; ignore if the runtime rejects them.
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

    #region Direct3D device creation

    private static ID3D11Device? CreateD3D11Device()
    {
        var featureLevels = new[]
        {
            FeatureLevel.Level_11_1,
            FeatureLevel.Level_11_0,
        };

        var result = D3D11.D3D11CreateDevice(
            null,
            DriverType.Hardware,
            DeviceCreationFlags.BgraSupport,
            featureLevels,
            out var device);

        if (result.Success)
        {
            return device;
        }

        // Fall back to WARP if no hardware device is available.
        result = D3D11.D3D11CreateDevice(
            null,
            DriverType.Warp,
            DeviceCreationFlags.BgraSupport,
            featureLevels,
            out device);

        return result.Success ? device : null;
    }

    [DllImport("d3d11.dll", ExactSpelling = true)]
    private static extern int CreateDirect3D11DeviceFromDXGIDevice(nint dxgiDevice, out nint graphicsDevice);

    private static IDirect3DDevice? CreateDirect3DDevice(ID3D11Device d3dDevice)
    {
        using var dxgiDevice = d3dDevice.QueryInterface<IDXGIDevice>();
        if (dxgiDevice is null)
        {
            return null;
        }

        var hr = CreateDirect3D11DeviceFromDXGIDevice(dxgiDevice.NativePointer, out var pInspectable);
        if (hr != 0)
        {
            return null;
        }

        var device = MarshalInterface<IDirect3DDevice>.FromAbi(pInspectable);
        Marshal.Release(pInspectable);
        return device;
    }

    #endregion

    #region GraphicsCaptureItem interop

    // Source-generated COM interop (ComWrappers-compatible). Classic [ComImport]
    // + Marshal.GetTypedObjectForIUnknown throws "Specified cast is not valid"
    // under CsWinRT, so these use [GeneratedComInterface] per the winapp CLI sample.
    [GeneratedComInterface]
    [System.Runtime.InteropServices.Guid("3628E81B-3CAC-4C60-B7F4-23CE0E0C3356")]
    internal partial interface IGraphicsCaptureItemInterop
    {
        [PreserveSig]
        int CreateForWindow(nint window, in Guid iid, out nint result);

        [PreserveSig]
        int CreateForMonitor(nint monitor, in Guid iid, out nint result);
    }

    [GeneratedComInterface]
    [System.Runtime.InteropServices.Guid("A9B3D012-3DF2-4EE3-B8D1-8695F457D3C1")]
    internal partial interface IDirect3DDxgiInterfaceAccess
    {
        [PreserveSig]
        int GetInterface(in Guid iid, out nint ppvObject);
    }

    private static unsafe GraphicsCaptureItem CreateCaptureItemForMonitor(nint hMonitor)
    {
        using var factory = ActivationFactory.Get("Windows.Graphics.Capture.GraphicsCaptureItem");
        nint interopPtr = 0;
        nint itemPtr = 0;
        try
        {
            Marshal.QueryInterface(factory.ThisPtr, in GraphicsCaptureItemInteropGuid, out interopPtr)
                .ThrowIfFailed("QueryInterface(IGraphicsCaptureItemInterop)");

            var interop = ComInterfaceMarshaller<IGraphicsCaptureItemInterop>.ConvertToManaged((void*)interopPtr)!;
            interopPtr = 0;

            interop.CreateForMonitor(hMonitor, in GraphicsCaptureItemGuid, out itemPtr)
                .ThrowIfFailed("IGraphicsCaptureItemInterop.CreateForMonitor");

            var item = MarshalInspectable<GraphicsCaptureItem>.FromAbi(itemPtr);
            itemPtr = 0;
            return item;
        }
        finally
        {
            if (itemPtr != 0)
            {
                Marshal.Release(itemPtr);
            }

            if (interopPtr != 0)
            {
                ComInterfaceMarshaller<IGraphicsCaptureItemInterop>.Free((void*)interopPtr);
            }
        }
    }

    private static unsafe ID3D11Texture2D GetTextureFromFrame(Direct3D11CaptureFrame frame)
    {
        var surfacePtr = ((IWinRTObject)frame.Surface).NativeObject.ThisPtr;
        nint accessPtr = 0;
        nint texturePtr = 0;
        try
        {
            Marshal.QueryInterface(surfacePtr, in Direct3DDxgiInterfaceAccessGuid, out accessPtr)
                .ThrowIfFailed("QueryInterface(IDirect3DDxgiInterfaceAccess)");

            var access = ComInterfaceMarshaller<IDirect3DDxgiInterfaceAccess>.ConvertToManaged((void*)accessPtr)!;
            accessPtr = 0;

            access.GetInterface(in D3D11Texture2DGuid, out texturePtr)
                .ThrowIfFailed("IDirect3DDxgiInterfaceAccess.GetInterface(ID3D11Texture2D)");

            var texture = new ID3D11Texture2D(texturePtr);
            texturePtr = 0;
            return texture;
        }
        finally
        {
            if (texturePtr != 0)
            {
                Marshal.Release(texturePtr);
            }

            if (accessPtr != 0)
            {
                ComInterfaceMarshaller<IDirect3DDxgiInterfaceAccess>.Free((void*)accessPtr);
            }
        }
    }

    #endregion
}

internal static class HResultExtensions
{
    public static void ThrowIfFailed(this int hr, string operation)
    {
        if (hr < 0)
        {
            throw new COMException($"{operation} failed with HRESULT 0x{hr:X8}.", hr);
        }
    }
}
