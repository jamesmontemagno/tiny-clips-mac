using Microsoft.UI.Input;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Windows.Foundation;
using Windows.Graphics;
using Windows.System;
using TinyClips.Core.Capture;

namespace TinyClips.App;

/// <summary>
/// A full-screen, borderless overlay that lets the user rubber-band a rectangle on the
/// primary monitor. Returns the selection as a monitor-relative <see cref="PixelRect"/>
/// in physical pixels, or null if cancelled (Esc / empty selection).
/// </summary>
public sealed partial class RegionSelectWindow : Window
{
    private readonly TaskCompletionSource<PixelRect?> _result = new();
    private Point _start;
    private bool _dragging;

    private RegionSelectWindow(MonitorInfo monitor)
    {
        InitializeComponent();

        ConfigurePresenter();
        AppWindow.Move(new PointInt32(monitor.X, monitor.Y));
        AppWindow.Resize(new SizeInt32(monitor.Width, monitor.Height));

        Activated += OnActivated;
    }

    /// <summary>Shows the overlay on the given monitor and resolves with the chosen region.</summary>
    public static Task<PixelRect?> RunAsync(MonitorInfo monitor)
    {
        var window = new RegionSelectWindow(monitor);
        window.Activate();
        return window._result.Task;
    }

    private void OnActivated(object sender, WindowActivatedEventArgs args)
    {
        Activated -= OnActivated;
        RootGrid.Focus(FocusState.Programmatic);
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

    private void OnPointerPressed(object sender, PointerRoutedEventArgs e)
    {
        _start = e.GetCurrentPoint(OverlayCanvas).Position;
        _dragging = true;
        Canvas.SetLeft(SelectionRect, _start.X);
        Canvas.SetTop(SelectionRect, _start.Y);
        SelectionRect.Width = 0;
        SelectionRect.Height = 0;
        SelectionRect.Visibility = Visibility.Visible;
        RootGrid.CapturePointer(e.Pointer);
    }

    private void OnPointerMoved(object sender, PointerRoutedEventArgs e)
    {
        if (!_dragging)
        {
            return;
        }

        var current = e.GetCurrentPoint(OverlayCanvas).Position;
        var x = Math.Min(_start.X, current.X);
        var y = Math.Min(_start.Y, current.Y);
        var width = Math.Abs(current.X - _start.X);
        var height = Math.Abs(current.Y - _start.Y);

        Canvas.SetLeft(SelectionRect, x);
        Canvas.SetTop(SelectionRect, y);
        SelectionRect.Width = width;
        SelectionRect.Height = height;
    }

    private void OnPointerReleased(object sender, PointerRoutedEventArgs e)
    {
        if (!_dragging)
        {
            return;
        }

        _dragging = false;
        RootGrid.ReleasePointerCapture(e.Pointer);

        var scale = RootGrid.XamlRoot?.RasterizationScale ?? 1.0;
        var x = Canvas.GetLeft(SelectionRect);
        var y = Canvas.GetTop(SelectionRect);
        var width = SelectionRect.Width;
        var height = SelectionRect.Height;

        if (width < 2 || height < 2)
        {
            Complete(null);
            return;
        }

        var region = new PixelRect(
            (int)Math.Round(x * scale),
            (int)Math.Round(y * scale),
            (int)Math.Round(width * scale),
            (int)Math.Round(height * scale));

        Complete(region);
    }

    private void OnKeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key == VirtualKey.Escape)
        {
            Complete(null);
        }
    }

    private void Complete(PixelRect? region)
    {
        _result.TrySetResult(region);
        Close();
    }
}
