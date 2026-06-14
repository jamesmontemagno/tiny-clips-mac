using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using TinyClips.Core.Capture;
using Windows.Graphics;

namespace TinyClips.App;

/// <summary>
/// A centered overlay that lets the user pick which physical display to capture when
/// more than one monitor is present. Resolves with the chosen monitor, or null on cancel.
/// </summary>
public sealed partial class ScreenPickerWindow : Window
{
    private sealed record ScreenItem(MonitorInfo Monitor, string Title, string Subtitle);

    private readonly TaskCompletionSource<MonitorInfo?> _result = new();
    private bool _completed;

    private ScreenPickerWindow(IReadOnlyList<MonitorInfo> monitors)
    {
        InitializeComponent();
        ConfigurePresenter();
        CenterOnPrimaryDisplay(560, 360);

        var items = new List<ScreenItem>();
        for (var i = 0; i < monitors.Count; i++)
        {
            var m = monitors[i];
            var title = m.IsPrimary ? $"Display {i + 1} (Primary)" : $"Display {i + 1}";
            items.Add(new ScreenItem(m, title, $"{m.Width} × {m.Height}"));
        }

        ScreenList.ItemsSource = items;
    }

    public static Task<MonitorInfo?> RunAsync(IReadOnlyList<MonitorInfo> monitors)
    {
        var window = new ScreenPickerWindow(monitors);
        window.Activate();
        return window._result.Task;
    }

    private void OnScreenClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is ScreenItem item)
        {
            Complete(item.Monitor);
        }
    }

    private void OnCancel(object sender, RoutedEventArgs e) => Complete(null);

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

    private void CenterOnPrimaryDisplay(int width, int height)
    {
        var scale = GetScale();
        var w = (int)Math.Round(width * scale);
        var h = (int)Math.Round(height * scale);

        if (DisplayArea.Primary?.WorkArea is { } work)
        {
            var x = work.X + Math.Max(0, (work.Width - w) / 2);
            var y = work.Y + Math.Max(0, (work.Height - h) / 2);
            AppWindow.Move(new PointInt32(x, y));
        }

        AppWindow.Resize(new SizeInt32(w, h));
    }

    private double GetScale()
    {
        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        var dpi = GetDpiForWindow(hwnd);
        return dpi <= 0 ? 1.0 : dpi / 96.0;
    }

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(nint hwnd);

    private void Complete(MonitorInfo? monitor)
    {
        if (_completed)
        {
            return;
        }

        _completed = true;
        _result.TrySetResult(monitor);
        Close();
    }
}
