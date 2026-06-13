using System.Runtime.InteropServices;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Input;
using Windows.Foundation;
using Windows.Graphics;
using WinRT.Interop;

namespace TinyClips.App;

/// <summary>
/// Small always-on-top panel shown while video or GIF recording is active.
/// </summary>
public sealed partial class RecordingIndicatorWindow : Window
{
    private const int WidthDip = 248;
    private const int HeightDip = 64;
    private const int TopOffsetDip = 24;

    private const uint WdaExcludeFromCapture = 0x11;

    private bool _stopRequested;
    private bool _closed;

    private bool _dragging;
    private Point _dragStart;

    public RecordingIndicatorWindow(string stopHint)
    {
        InitializeComponent();

        HotKeyText.Text = string.IsNullOrWhiteSpace(stopHint)
            ? "Stop from tray"
            : $"Stop: {stopHint}";

        ConfigurePresenter();
        Closed += OnClosed;
    }

    public Action? StopRequested { get; set; }

    public void ShowNear()
    {
        PositionNearPrimaryWorkArea();
        AppWindow.Show(false);

        // Exclude the floating panel from screen capture so it never appears in the
        // recorded video/GIF.
        var hwnd = WindowNative.GetWindowHandle(this);
        SetWindowDisplayAffinity(hwnd, WdaExcludeFromCapture);
    }

    public void UpdateElapsed(TimeSpan elapsed)
    {
        if (elapsed < TimeSpan.Zero)
        {
            elapsed = TimeSpan.Zero;
        }

        var totalMinutes = (int)Math.Min(99, elapsed.TotalMinutes);
        ElapsedText.Text = $"{totalMinutes:00}:{elapsed.Seconds:00}";
    }

    public void ClosePanel()
    {
        if (_closed)
        {
            return;
        }

        _closed = true;
        StopRequested = null;
        Close();
    }

    private void OnStopClick(object sender, RoutedEventArgs e)
    {
        if (_stopRequested)
        {
            return;
        }

        _stopRequested = true;
        StopButton.IsEnabled = false;

        var callback = StopRequested;
        StopRequested = null;
        callback?.Invoke();
    }

    // Drag-anywhere support: pressing the Stop button is handled by the Button itself
    // (it marks the pointer event handled), so dragging only begins on the panel surface.
    private void OnPointerPressed(object sender, PointerRoutedEventArgs e)
    {
        if (sender is not UIElement element)
        {
            return;
        }

        _dragStart = e.GetCurrentPoint(element).Position;
        _dragging = element.CapturePointer(e.Pointer);
    }

    private void OnPointerMoved(object sender, PointerRoutedEventArgs e)
    {
        if (!_dragging || sender is not UIElement element)
        {
            return;
        }

        var current = e.GetCurrentPoint(element).Position;
        var scale = GetScale();
        var dx = (int)Math.Round((current.X - _dragStart.X) * scale);
        var dy = (int)Math.Round((current.Y - _dragStart.Y) * scale);

        if (dx == 0 && dy == 0)
        {
            return;
        }

        var pos = AppWindow.Position;
        AppWindow.Move(new PointInt32(pos.X + dx, pos.Y + dy));
    }

    private void OnPointerReleased(object sender, PointerRoutedEventArgs e)
    {
        if (sender is not UIElement element)
        {
            return;
        }

        _dragging = false;
        element.ReleasePointerCapture(e.Pointer);
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
        StopRequested = null;
    }

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(nint hwnd);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowDisplayAffinity(nint hWnd, uint dwAffinity);
}
