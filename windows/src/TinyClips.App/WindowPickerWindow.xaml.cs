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
        CoverPrimaryDisplay();

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

    private void CoverPrimaryDisplay()
    {
        if (DisplayArea.Primary?.OuterBounds is { } bounds)
        {
            AppWindow.Move(new PointInt32(bounds.X, bounds.Y));
            AppWindow.Resize(new SizeInt32(bounds.Width, bounds.Height));
        }
    }

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
