using Microsoft.UI.Dispatching;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Windows.Graphics;

namespace TinyClips.App;

/// <summary>
/// A borderless, always-on-top countdown shown before a capture begins. Counts down
/// from the requested number of seconds and completes once it reaches zero.
/// </summary>
public sealed partial class CountdownWindow : Window
{
    private readonly DispatcherQueueTimer _timer;
    private readonly TaskCompletionSource _completed = new();
    private int _remaining;

    private CountdownWindow(int seconds)
    {
        InitializeComponent();

        _remaining = Math.Max(1, seconds);
        CountText.Text = _remaining.ToString();

        ConfigurePresenter();
        CenterOnPrimaryDisplay();

        _timer = DispatcherQueue.CreateTimer();
        _timer.Interval = TimeSpan.FromSeconds(1);
        _timer.Tick += OnTick;
    }

    /// <summary>Shows a countdown overlay and returns when it finishes.</summary>
    public static Task RunAsync(int seconds)
    {
        var window = new CountdownWindow(seconds);
        window.Activate();
        window._timer.Start();
        return window._completed.Task;
    }

    private void OnTick(DispatcherQueueTimer sender, object args)
    {
        _remaining--;
        if (_remaining <= 0)
        {
            _timer.Stop();
            _timer.Tick -= OnTick;
            _completed.TrySetResult();
            Close();
            return;
        }

        CountText.Text = _remaining.ToString();
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

    private void CenterOnPrimaryDisplay()
    {
        var area = DisplayArea.Primary?.WorkArea;

        // Window is sized to the compact badge (DIPs scaled to physical pixels).
        const int sizeDip = 92;
        var scale = GetScale();
        var size = (int)Math.Round(sizeDip * scale);
        AppWindow.Resize(new SizeInt32(size, size));

        if (area is { } work)
        {
            var x = work.X + ((work.Width - size) / 2);
            var y = work.Y + ((work.Height - size) / 2);
            AppWindow.Move(new PointInt32(x, y));
        }
    }

    private double GetScale()
    {
        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        var dpi = GetDpiForWindow(hwnd);
        return dpi <= 0 ? 1.0 : dpi / 96.0;
    }

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(nint hwnd);
}
