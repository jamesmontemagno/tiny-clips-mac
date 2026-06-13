using Microsoft.UI.Input;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using TinyClips.Core.Models;
using Windows.Graphics;
using Windows.System;

namespace TinyClips.App;

/// <summary>How the user chose to scope a capture.</summary>
public enum CapturePickerMode
{
    Region,
    Screen,
    Window,
}

/// <summary>The user's choice from the capture picker bar.</summary>
public sealed record CapturePickerResult(CapturePickerMode Mode, bool CountdownEnabled, int CountdownDuration);

/// <summary>
/// A floating, borderless picker bar shown near the top of the primary display when a
/// capture starts. Lets the user choose Region / Screen / Window and a countdown, with
/// R / S / W / Esc keyboard shortcuts — mirroring the macOS CapturePickerPanel.
/// </summary>
public sealed partial class CapturePickerWindow : Window
{
    private static readonly int[] CountdownOptions = { 1, 2, 3, 5, 10 };

    private readonly TaskCompletionSource<CapturePickerResult?> _result = new();
    private bool _countdownEnabled;
    private int _countdownDuration;
    private bool _completed;

    private bool _dragging;
    private Windows.Foundation.Point _dragStart;

    private CapturePickerWindow(CaptureType captureType, bool countdownEnabled, int countdownDuration)
    {
        InitializeComponent();

        _countdownEnabled = countdownEnabled;
        _countdownDuration = countdownDuration <= 0 ? 3 : countdownDuration;

        ModeIcon.Glyph = captureType switch
        {
            CaptureType.Video => "\uE714",
            CaptureType.Gif => "\uE786",
            _ => "\uE722",
        };
        ModeLabel.Text = captureType switch
        {
            CaptureType.Video => "Video",
            CaptureType.Gif => "GIF",
            _ => "Screenshot",
        };

        BuildTimerFlyout();
        UpdateTimerLabel();
        ConfigurePresenter();

        RootGrid.KeyDown += OnKeyDown;
        Activated += OnActivated;
    }

    public static Task<CapturePickerResult?> RunAsync(CaptureType captureType, bool countdownEnabled, int countdownDuration)
    {
        var window = new CapturePickerWindow(captureType, countdownEnabled, countdownDuration);
        window.Activate();
        return window._result.Task;
    }

    private void OnActivated(object sender, WindowActivatedEventArgs args)
    {
        if (args.WindowActivationState == WindowActivationState.Deactivated)
        {
            return;
        }

        Activated -= OnActivated;
        // Size to content, then position near the top-center of the primary work area.
        RootGrid.UpdateLayout();
        RootGrid.Measure(new Windows.Foundation.Size(double.PositiveInfinity, double.PositiveInfinity));
        var scale = RootGrid.XamlRoot?.RasterizationScale ?? 1.0;
        var width = (int)Math.Ceiling(RootGrid.DesiredSize.Width * scale);
        var height = (int)Math.Ceiling(RootGrid.DesiredSize.Height * scale);
        width = Math.Max(width, (int)(360 * scale));
        height = Math.Max(height, (int)(64 * scale));

        AppWindow.Resize(new SizeInt32(width, height));
        if (DisplayArea.Primary?.WorkArea is { } work)
        {
            var x = work.X + ((work.Width - width) / 2);
            var y = work.Y + (int)(72 * scale);
            AppWindow.Move(new PointInt32(x, y));
        }

        RootGrid.Focus(FocusState.Programmatic);
    }

    private void BuildTimerFlyout()
    {
        var off = new MenuFlyoutItem { Text = "Off" };
        off.Click += (_, _) =>
        {
            _countdownEnabled = false;
            UpdateTimerLabel();
        };
        TimerFlyout.Items.Add(off);
        TimerFlyout.Items.Add(new MenuFlyoutSeparator());

        foreach (var seconds in CountdownOptions)
        {
            var item = new MenuFlyoutItem { Text = $"{seconds}s" };
            item.Click += (_, _) =>
            {
                _countdownEnabled = true;
                _countdownDuration = seconds;
                UpdateTimerLabel();
            };
            TimerFlyout.Items.Add(item);
        }
    }

    private void UpdateTimerLabel()
    {
        TimerLabel.Text = _countdownEnabled ? $"{_countdownDuration}s" : "Off";
        AutomationProperties.SetName(TimerButton, $"Countdown timer, {(_countdownEnabled ? _countdownDuration + " seconds" : "off")}");
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

    private void OnRegion(object sender, RoutedEventArgs e) => Complete(CapturePickerMode.Region);

    private void OnScreen(object sender, RoutedEventArgs e) => Complete(CapturePickerMode.Screen);

    private void OnWindow(object sender, RoutedEventArgs e) => Complete(CapturePickerMode.Window);

    private void OnCancel(object sender, RoutedEventArgs e) => Complete(null);

    // Drag-anywhere support: the R / S / W / timer / cancel buttons handle their own
    // pointer events (marking them handled), so a drag only starts on the bar background.
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

    private double GetScale()
    {
        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        var dpi = GetDpiForWindow(hwnd);
        return dpi <= 0 ? 1.0 : dpi / 96.0;
    }

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(nint hwnd);

    private void OnKeyDown(object sender, KeyRoutedEventArgs e)
    {
        switch (e.Key)
        {
            case VirtualKey.Escape:
                Complete(null);
                break;
            case VirtualKey.R:
                Complete(CapturePickerMode.Region);
                break;
            case VirtualKey.S:
                Complete(CapturePickerMode.Screen);
                break;
            case VirtualKey.W:
                Complete(CapturePickerMode.Window);
                break;
        }
    }

    private void Complete(CapturePickerMode? mode)
    {
        if (_completed)
        {
            return;
        }

        _completed = true;
        _result.TrySetResult(mode is { } m ? new CapturePickerResult(m, _countdownEnabled, _countdownDuration) : null);
        Close();
    }
}
