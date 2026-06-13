using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.Graphics;
using WinRT.Interop;

namespace TinyClips.App;

/// <summary>
/// A centered overlay listing visible top-level windows so the user can pick one to
/// capture. Resolves with the chosen window handle, or null on cancel.
/// </summary>
public sealed partial class WindowPickerWindow : Window
{
    private readonly TaskCompletionSource<nint?> _result = new();
    private bool _completed;

    private WindowPickerWindow()
    {
        InitializeComponent();
        ConfigurePresenter();
        CenterOnPrimaryDisplay(520, 640);

        var ownHwnd = WindowNative.GetWindowHandle(this);
        WindowList.ItemsSource = WindowEnumerator.GetWindows(ownHwnd);
    }

    public static Task<nint?> RunAsync()
    {
        var window = new WindowPickerWindow();
        window.Activate();
        return window._result.Task;
    }

    private void OnWindowClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is WindowEntry entry)
        {
            Complete(entry.Hwnd);
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
        var hwnd = WindowNative.GetWindowHandle(this);
        var dpi = GetDpiForWindow(hwnd);
        return dpi <= 0 ? 1.0 : dpi / 96.0;
    }

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(nint hwnd);

    private void Complete(nint? hwnd)
    {
        if (_completed)
        {
            return;
        }

        _completed = true;
        _result.TrySetResult(hwnd);
        Close();
    }
}
