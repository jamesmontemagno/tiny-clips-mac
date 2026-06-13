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
        CoverPrimaryDisplay();

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

    private void CoverPrimaryDisplay()
    {
        if (DisplayArea.Primary?.OuterBounds is { } bounds)
        {
            AppWindow.Move(new PointInt32(bounds.X, bounds.Y));
            AppWindow.Resize(new SizeInt32(bounds.Width, bounds.Height));
        }
    }

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
