using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
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

    private bool _stopRequested;
    private bool _closed;

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
}
