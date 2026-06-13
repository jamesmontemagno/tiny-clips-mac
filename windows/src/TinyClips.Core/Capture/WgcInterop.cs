using System.Runtime.InteropServices;
using System.Runtime.InteropServices.Marshalling;
using Vortice.Direct3D;
using Vortice.Direct3D11;
using Vortice.DXGI;
using Windows.Foundation.Metadata;
using Windows.Graphics.Capture;
using Windows.Graphics.DirectX.Direct3D11;
using WinRT;

namespace TinyClips.Core.Capture;

/// <summary>
/// Shared Windows.Graphics.Capture (WGC) + Direct3D 11 interop used by both the
/// single-frame screenshot engine and the continuous video/GIF recorders.
///
/// Uses source-generated COM interop (ComWrappers-compatible). Classic
/// <c>[ComImport]</c> + <c>Marshal.GetTypedObjectForIUnknown</c> throws
/// "Specified cast is not valid" under CsWinRT, so these use
/// <c>[GeneratedComInterface]</c> per the winapp CLI sample.
/// </summary>
internal static partial class WgcInterop
{
    private static readonly Guid GraphicsCaptureItemGuid = new("79C3F95B-31F7-4EC2-A464-632EF5D30760");
    private static readonly Guid GraphicsCaptureItemInteropGuid = new("3628E81B-3CAC-4C60-B7F4-23CE0E0C3356");
    private static readonly Guid Direct3DDxgiInterfaceAccessGuid = new("A9B3D012-3DF2-4EE3-B8D1-8695F457D3C1");
    private static readonly Guid D3D11Texture2DGuid = new("6F15AAF2-D208-4E89-9AB4-489535D34F9C");

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

    internal static ID3D11Device? CreateD3D11Device()
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

    internal static IDirect3DDevice? CreateDirect3DDevice(ID3D11Device d3dDevice)
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

    internal static unsafe GraphicsCaptureItem CreateCaptureItemForMonitor(nint hMonitor)
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

    internal static unsafe ID3D11Texture2D GetTextureFromFrame(Direct3D11CaptureFrame frame)
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

    /// <summary>Best-effort toggle of cursor capture and the capture border.</summary>
    internal static void TryConfigureSession(GraphicsCaptureSession session, bool includeCursor)
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
