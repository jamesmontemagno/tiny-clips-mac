using Microsoft.UI.Input;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media.Imaging;
using Microsoft.Extensions.DependencyInjection;
using System.Runtime.InteropServices.WindowsRuntime;
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
    private readonly TaskCompletionSource<PixelRect?> _result =
        new(TaskCreationOptions.RunContinuationsAsynchronously);
    private readonly CapturedFrame? _backdropFrame;
    private Point _start;
    private bool _dragging;
    private bool _completed;

    private RegionSelectWindow(MonitorInfo monitor, CapturedFrame? backdropFrame)
    {
        _backdropFrame = backdropFrame;

        InitializeComponent();

        ConfigurePresenter();
        AppWindow.Move(new PointInt32(monitor.X, monitor.Y));
        AppWindow.Resize(new SizeInt32(monitor.Width, monitor.Height));

        ShowBackdrop();
        Activated += OnActivated;
        Closed += OnClosed;
    }

    /// <summary>Shows the overlay on the given monitor and resolves with the chosen region.</summary>
    public static async Task<PixelRect?> RunAsync(MonitorInfo monitor)
    {
        // Snapshot the monitor BEFORE the overlay is shown so the dim panels never get baked
        // into the backdrop image (otherwise we'd capture our own darkening).
        CapturedFrame? frame = null;
        try
        {
            var capture = App.Services.GetRequiredService<IScreenCaptureService>();
            frame = await capture.CaptureMonitorAsync(monitor.HMonitor);
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"Region backdrop capture failed: {ex}");
        }

        var window = new RegionSelectWindow(monitor, frame);
        window.Activate();
        return await window._result.Task;
    }

    private void OnActivated(object sender, WindowActivatedEventArgs args)
    {
        Activated -= OnActivated;
        RootGrid.Focus(FocusState.Programmatic);
    }

    /// <summary>
    /// Paints the pre-captured monitor snapshot behind the dim overlay so the user sees a true
    /// view of the screen, with only the area outside the selection darkened.
    /// </summary>
    private void ShowBackdrop()
    {
        if (_backdropFrame is null)
        {
            return;
        }

        try
        {
            var bitmap = new WriteableBitmap(_backdropFrame.Width, _backdropFrame.Height);
            using (var stream = bitmap.PixelBuffer.AsStream())
            {
                stream.Write(_backdropFrame.BgraPixels, 0, _backdropFrame.BgraPixels.Length);
            }

            Backdrop.Source = bitmap;
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"Region backdrop paint failed: {ex}");
        }
    }

    private void OnOverlaySizeChanged(object sender, SizeChangedEventArgs e)
    {
        FullDim.Width = e.NewSize.Width;
        FullDim.Height = e.NewSize.Height;
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

        // Swap the uniform dim for the hole-punch panels so the selection stays clear.
        FullDim.Visibility = Visibility.Collapsed;
        TopDim.Visibility = Visibility.Visible;
        BottomDim.Visibility = Visibility.Visible;
        LeftDim.Visibility = Visibility.Visible;
        RightDim.Visibility = Visibility.Visible;

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

        UpdateDimPanels(x, y, width, height);
    }

    /// <summary>
    /// Positions the four dim panels so that everything except the selection rectangle is
    /// darkened, giving a clear, un-dimmed view of the area being captured.
    /// </summary>
    private void UpdateDimPanels(double x, double y, double width, double height)
    {
        var w = OverlayCanvas.ActualWidth;
        var h = OverlayCanvas.ActualHeight;

        Canvas.SetLeft(TopDim, 0);
        Canvas.SetTop(TopDim, 0);
        TopDim.Width = w;
        TopDim.Height = Math.Max(0, y);

        Canvas.SetLeft(BottomDim, 0);
        Canvas.SetTop(BottomDim, y + height);
        BottomDim.Width = w;
        BottomDim.Height = Math.Max(0, h - (y + height));

        Canvas.SetLeft(LeftDim, 0);
        Canvas.SetTop(LeftDim, y);
        LeftDim.Width = Math.Max(0, x);
        LeftDim.Height = height;

        Canvas.SetLeft(RightDim, x + width);
        Canvas.SetTop(RightDim, y);
        RightDim.Width = Math.Max(0, w - (x + width));
        RightDim.Height = height;
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
        if (_completed)
        {
            return;
        }

        _completed = true;
        _dragging = false;
        RootGrid.ReleasePointerCaptures();
        Closed -= OnClosed;
        try
        {
            Close();
        }
        finally
        {
            _result.TrySetResult(region);
        }
    }

    private void OnClosed(object sender, WindowEventArgs args)
    {
        if (_completed)
        {
            return;
        }

        _completed = true;
        _dragging = false;
        _result.TrySetResult(null);
    }
}
