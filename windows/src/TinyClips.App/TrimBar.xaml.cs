using System;
using Microsoft.UI.Input;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;

namespace TinyClips.App;

/// <summary>
/// A single-line trim control modeled on the macOS app: a dimmed track with an accent-colored
/// selected region between two draggable handles plus a movable playhead. All values are
/// normalized fractions in the range [0, 1]; the hosting window maps them to seconds or frames.
/// </summary>
/// <remarks>
/// The control raises <see cref="StartFractionChanged"/>, <see cref="EndFractionChanged"/> and
/// <see cref="SeekRequested"/> only in response to user pointer input. Assigning the matching
/// properties (e.g. from the host while clamping) re-lays out without re-raising events, so there
/// is no feedback loop.
/// </remarks>
public sealed partial class TrimBar : UserControl
{
    private enum DragMode
    {
        None,
        Start,
        End,
        Range,
        Seek,
    }

    private const double HandleWidth = 14.0;
    private const double TrackHeight = 36.0;
    private const double HandleGrab = 12.0;

    private static readonly InputSystemCursor SizeCursor = InputSystemCursor.Create(InputSystemCursorShape.SizeWestEast);
    private static readonly InputSystemCursor MoveCursor = InputSystemCursor.Create(InputSystemCursorShape.SizeAll);
    private static readonly InputSystemCursor ArrowCursor = InputSystemCursor.Create(InputSystemCursorShape.Arrow);

    private DragMode _drag = DragMode.None;
    private double _start;
    private double _end = 1.0;
    private double _play;

    // Anchors captured at the start of a range drag so the selection moves rigidly with the cursor.
    private double _rangeGrabFraction;
    private double _rangeStartAtGrab;
    private double _rangeEndAtGrab;

    public TrimBar()
    {
        InitializeComponent();

        PointerPressed += OnPointerPressed;
        PointerMoved += OnPointerMoved;
        PointerReleased += OnPointerReleased;
        PointerCaptureLost += OnPointerCaptureLost;
        PointerExited += OnPointerExited;
        SizeChanged += (_, _) => LayoutParts();
    }

    /// <summary>Raised while the user drags the start handle. Carries the new start fraction.</summary>
    public event EventHandler<double>? StartFractionChanged;

    /// <summary>Raised while the user drags the end handle. Carries the new end fraction.</summary>
    public event EventHandler<double>? EndFractionChanged;

    /// <summary>Raised while the user scrubs the track body. Carries the requested playhead fraction.</summary>
    public event EventHandler<double>? SeekRequested;

    /// <summary>
    /// Raised while the user drags the selected region as a whole. Carries the new start and end
    /// fractions (the selection width is preserved).
    /// </summary>
    public event EventHandler<(double Start, double End)>? RangeChanged;

    public double StartFraction
    {
        get => _start;
        set
        {
            _start = Clamp01(value);
            LayoutParts();
        }
    }

    public double EndFraction
    {
        get => _end;
        set
        {
            _end = Clamp01(value);
            LayoutParts();
        }
    }

    public double PlayheadFraction
    {
        get => _play;
        set
        {
            _play = Clamp01(value);
            LayoutParts();
        }
    }

    private double Usable => Math.Max(1.0, ActualWidth - HandleWidth);

    private static double Clamp01(double value) => Math.Clamp(value, 0.0, 1.0);

    private void LayoutParts()
    {
        var w = ActualWidth;
        var h = ActualHeight;
        if (w <= 0 || h <= 0)
        {
            return;
        }

        var half = HandleWidth / 2.0;
        var top = (h - TrackHeight) / 2.0;
        var usable = Math.Max(1.0, w - HandleWidth);
        double X(double f) => half + f * usable;

        var sx = X(_start);
        var ex = X(_end);
        var px = X(_play);

        TrackBg.Width = w;
        TrackBg.Height = TrackHeight;
        Canvas.SetLeft(TrackBg, 0);
        Canvas.SetTop(TrackBg, top);

        ActiveRegion.Width = Math.Max(0, ex - sx);
        ActiveRegion.Height = TrackHeight;
        Canvas.SetLeft(ActiveRegion, sx);
        Canvas.SetTop(ActiveRegion, top);

        Playhead.Height = TrackHeight + 8;
        Canvas.SetLeft(Playhead, px - 1);
        Canvas.SetTop(Playhead, top - 4);

        StartHandle.Width = HandleWidth;
        StartHandle.Height = TrackHeight;
        Canvas.SetLeft(StartHandle, sx - half);
        Canvas.SetTop(StartHandle, top);

        EndHandle.Width = HandleWidth;
        EndHandle.Height = TrackHeight;
        Canvas.SetLeft(EndHandle, ex - half);
        Canvas.SetTop(EndHandle, top);
    }

    private double FractionFromX(double x) => Clamp01((x - HandleWidth / 2.0) / Usable);

    private void OnPointerPressed(object sender, PointerRoutedEventArgs e)
    {
        var x = e.GetCurrentPoint(this).Position.X;
        var half = HandleWidth / 2.0;
        var usable = Usable;
        var sx = half + _start * usable;
        var ex = half + _end * usable;
        var dStart = Math.Abs(x - sx);
        var dEnd = Math.Abs(x - ex);
        var fraction = FractionFromX(x);

        if (dStart <= HandleGrab && dStart <= dEnd)
        {
            _drag = DragMode.Start;
            ApplyDrag(fraction);
        }
        else if (dEnd <= HandleGrab)
        {
            _drag = DragMode.End;
            ApplyDrag(fraction);
        }
        else if (x > sx && x < ex)
        {
            // Press inside the selected region: drag the whole selection, preserving its width.
            _drag = DragMode.Range;
            _rangeGrabFraction = fraction;
            _rangeStartAtGrab = _start;
            _rangeEndAtGrab = _end;
        }
        else
        {
            _drag = DragMode.Seek;
            ApplyDrag(fraction);
        }

        CapturePointer(e.Pointer);
        e.Handled = true;
    }

    private void OnPointerMoved(object sender, PointerRoutedEventArgs e)
    {
        var x = e.GetCurrentPoint(this).Position.X;
        if (_drag == DragMode.None)
        {
            UpdateHoverCursor(x);
            return;
        }

        ApplyDrag(FractionFromX(x));
        e.Handled = true;
    }

    private void ApplyDrag(double fraction)
    {
        switch (_drag)
        {
            case DragMode.Start:
                StartFractionChanged?.Invoke(this, fraction);
                break;
            case DragMode.End:
                EndFractionChanged?.Invoke(this, fraction);
                break;
            case DragMode.Range:
                var width = _rangeEndAtGrab - _rangeStartAtGrab;
                var delta = fraction - _rangeGrabFraction;
                var newStart = Math.Clamp(_rangeStartAtGrab + delta, 0.0, 1.0 - width);
                var newEnd = newStart + width;
                RangeChanged?.Invoke(this, (newStart, newEnd));
                break;
            case DragMode.Seek:
                SeekRequested?.Invoke(this, fraction);
                break;
        }
    }

    private void OnPointerReleased(object sender, PointerRoutedEventArgs e)
    {
        _drag = DragMode.None;
        ReleasePointerCapture(e.Pointer);
    }

    private void OnPointerCaptureLost(object sender, PointerRoutedEventArgs e) => _drag = DragMode.None;

    private void OnPointerExited(object sender, PointerRoutedEventArgs e)
    {
        if (_drag == DragMode.None)
        {
            ProtectedCursor = ArrowCursor;
        }
    }

    private void UpdateHoverCursor(double x)
    {
        var half = HandleWidth / 2.0;
        var usable = Usable;
        var sx = half + _start * usable;
        var ex = half + _end * usable;
        var nearHandle = Math.Min(Math.Abs(x - sx), Math.Abs(x - ex)) <= HandleGrab;

        if (nearHandle)
        {
            ProtectedCursor = SizeCursor;
        }
        else if (x > sx && x < ex)
        {
            ProtectedCursor = MoveCursor;
        }
        else
        {
            ProtectedCursor = ArrowCursor;
        }
    }
}
