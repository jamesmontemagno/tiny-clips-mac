using System.Runtime.InteropServices;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Windows.Graphics;
using WinRT.Interop;
using TinyClips.Core.Models;

namespace TinyClips.App;

/// <summary>
/// Small always-on-top panel shown after the user stops a recording while the clip is being
/// encoded/finalized. Mirrors <see cref="RecordingIndicatorWindow"/>'s floating-panel recipe:
/// borderless, always-on-top, positioned near the top of the primary work area, and excluded
/// from screen capture.
/// </summary>
public sealed partial class ProcessingIndicatorWindow : Window
{
    private const int WidthDip = 220;
    private const int HeightDip = 64;
    private const int TopOffsetDip = 24;

    private const uint WdaExcludeFromCapture = 0x11;

    private bool _closed;

    public ProcessingIndicatorWindow(CaptureType type)
    {
        InitializeComponent();

        CaptionText.Text = type == CaptureType.Gif
            ? "Finalizing your GIF"
            : "Finalizing your video";

        ConfigurePresenter();
        Closed += OnClosed;
    }

    public void ShowNear()
    {
        PositionNearPrimaryWorkArea();
        AppWindow.Show(false);

        // Keep the panel out of any concurrent capture.
        var hwnd = WindowNative.GetWindowHandle(this);
        SetWindowDisplayAffinity(hwnd, WdaExcludeFromCapture);
    }

    public void ClosePanel()
    {
        if (_closed)
        {
            return;
        }

        _closed = true;
        Close();
    }

    private void ConfigurePresenter()
    {
        if (AppWindow.Presenter is OverlappedPresenter presenter)
        {
            presenter.SetBorderAndTitleBar(false, false);
            presenter.IsAlwaysOnTop = true;
            presenter.IsMaximizable = false;
            presenter.IsMinimizable = false;
            presenter.IsResizable = false;
        }

        AppWindow.IsShownInSwitchers = false;
    }

    private void PositionNearPrimaryWorkArea()
    {
        var scale = GetScale();
        var width = (int)Math.Round(WidthDip * scale);
        var height = (int)Math.Round(HeightDip * scale);
        var topOffset = (int)Math.Round(TopOffsetDip * scale);

        AppWindow.Resize(new SizeInt32(width, height));

        if (DisplayArea.Primary?.WorkArea is { } work)
        {
            var x = work.X + Math.Max(0, (work.Width - width) / 2);
            var y = work.Y + topOffset;
            AppWindow.Move(new PointInt32(x, y));
        }
    }

    private double GetScale()
    {
        var hwnd = WindowNative.GetWindowHandle(this);
        var dpi = GetDpiForWindow(hwnd);
        return dpi <= 0 ? 1.0 : dpi / 96.0;
    }

    private void OnClosed(object sender, WindowEventArgs args)
    {
        _closed = true;
    }

    [DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(nint hwnd);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowDisplayAffinity(nint hWnd, uint dwAffinity);
}
