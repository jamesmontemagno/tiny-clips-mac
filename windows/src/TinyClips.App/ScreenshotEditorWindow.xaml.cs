using System;
using System.Collections.Generic;
using System.Linq;
using System.Numerics;
using System.Runtime.InteropServices.WindowsRuntime;
using System.Threading.Tasks;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Graphics.Canvas;
using Microsoft.Graphics.Canvas.Effects;
using Microsoft.Graphics.Canvas.Geometry;
using Microsoft.Graphics.Canvas.Text;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Microsoft.UI.Xaml.Shapes;
using TinyClips.Core.Models;
using TinyClips.Core.Services;
using Windows.Foundation;
using Windows.Graphics.Imaging;
using Windows.Storage;
using Windows.Storage.Pickers;
using Windows.Storage.Streams;
using Windows.UI;
using Windows.ApplicationModel.DataTransfer;

namespace TinyClips.App;

/// <summary>
/// Screenshot editor with annotation parity to the macOS app: crop plus rectangle, ellipse,
/// arrow, line, freehand draw, text, numbered badges and redaction. Annotations are stored in
/// image-pixel coordinates and previewed live with XAML shapes; on export they are baked into
/// the bitmap at full resolution with Win2D so output matches the preview exactly.
/// </summary>
public sealed partial class ScreenshotEditorWindow : Window
{
    private enum EditTool
    {
        Select,
        Crop,
        Rectangle,
        Ellipse,
        Arrow,
        Line,
        Pen,
        Text,
        Counter,
        Redact,
    }

    private sealed class Annotation
    {
        public EditTool Tool { get; set; }
        public Rect Bounds { get; set; }
        public Color Color { get; set; }
        public double Thickness { get; set; }
        public string Text { get; set; } = string.Empty;
        public int Number { get; set; }
        public List<Vector2> Points { get; } = new();
    }

    private readonly string _filePath;
    private SoftwareBitmap? _bitmap;

    private readonly List<Annotation> _annotations = new();
    private Annotation? _activeAnnotation;
    private Annotation? _selectedAnnotation;
    private EditTool _tool = EditTool.Crop;
    private Color _strokeColor = Colors.Red;
    private double _strokeThickness = 6;
    private int _counterValue = 1;

    private bool _dragging;
    private Point _dragStart;
    private Annotation? _movingAnnotation;
    private Point _moveOffset;
    private Point _pendingTextOrigin;

    public ScreenshotEditorWindow(string filePath)
    {
        _filePath = filePath;

        InitializeComponent();

        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);
        AppWindow.Resize(new Windows.Graphics.SizeInt32(1100, 800));
        (AppWindow.Presenter as Microsoft.UI.Windowing.OverlappedPresenter)?.Maximize();

        var settings = App.Services.GetRequiredService<ICaptureSettings>();
        RootGrid.RequestedTheme = settings.Theme switch
        {
            AppTheme.Light => ElementTheme.Light,
            AppTheme.Dark => ElementTheme.Dark,
            _ => ElementTheme.Default,
        };

        AnnotationColorPicker.Color = _strokeColor;
        ColorSwatch.Background = new SolidColorBrush(_strokeColor);
        ThicknessCombo.SelectedIndex = 1;
        SelectTool(EditTool.Crop);

        RootGrid.KeyDown += OnRootKeyDown;

        _ = LoadAsync();
    }

    private async Task LoadAsync()
    {
        try
        {
            var file = await StorageFile.GetFileFromPathAsync(_filePath);
            using var stream = await file.OpenAsync(FileAccessMode.Read);
            var decoder = await BitmapDecoder.CreateAsync(stream);
            var bitmap = await decoder.GetSoftwareBitmapAsync(
                BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied);
            await SetBitmapAsync(bitmap);
            _annotations.Clear();
            _counterValue = 1;
            RedrawOverlay();
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"Editor load failed: {ex}");
        }
    }

    private async Task SetBitmapAsync(SoftwareBitmap bitmap)
    {
        _bitmap?.Dispose();
        _bitmap = bitmap;

        var source = new SoftwareBitmapSource();
        await source.SetBitmapAsync(bitmap);
        PreviewImage.Source = source;

        ClearSelection();
    }

    // -- Tool selection -------------------------------------------------------

    private void OnToolClick(object sender, RoutedEventArgs e)
    {
        if (sender is ToggleButton { Tag: string tag } && Enum.TryParse<EditTool>(tag, out var tool))
        {
            SelectTool(tool);
        }
    }

    private void SelectTool(EditTool tool)
    {
        _tool = tool;
        _selectedAnnotation = null;
        CommitPendingText();

        foreach (var (button, value) in ToolButtons())
        {
            button.IsChecked = value == tool;
        }

        var annotating = tool is not (EditTool.Select or EditTool.Crop);
        ThicknessCombo.IsEnabled = annotating;
        ColorButton.IsEnabled = annotating;

        HintText.Text = tool switch
        {
            EditTool.Crop => "Drag to select an area, then choose Apply crop.",
            EditTool.Select => "Click an annotation to select it; drag to move, Del to remove.",
            EditTool.Text => "Click where you want to add text.",
            EditTool.Counter => "Click to drop a numbered badge.",
            EditTool.Pen => "Drag to draw freehand.",
            EditTool.Redact => "Drag over content to redact it.",
            _ => "Drag on the image to draw.",
        };

        ApplyCropButton.IsEnabled = false;
        SelectionRect.Visibility = Visibility.Collapsed;
        RedrawOverlay();
    }

    private IEnumerable<(ToggleButton Button, EditTool Tool)> ToolButtons()
    {
        yield return (ToolSelect, EditTool.Select);
        yield return (ToolCrop, EditTool.Crop);
        yield return (ToolRectangle, EditTool.Rectangle);
        yield return (ToolEllipse, EditTool.Ellipse);
        yield return (ToolArrow, EditTool.Arrow);
        yield return (ToolLine, EditTool.Line);
        yield return (ToolPen, EditTool.Pen);
        yield return (ToolText, EditTool.Text);
        yield return (ToolCounter, EditTool.Counter);
        yield return (ToolRedact, EditTool.Redact);
    }

    private void OnColorChanged(ColorPicker sender, ColorChangedEventArgs args)
    {
        _strokeColor = args.NewColor;
        ColorSwatch.Background = new SolidColorBrush(_strokeColor);
        if (_selectedAnnotation is not null)
        {
            _selectedAnnotation.Color = _strokeColor;
            RedrawOverlay();
        }
    }

    private void OnThicknessChanged(object sender, SelectionChangedEventArgs e)
    {
        if (ThicknessCombo.SelectedItem is ComboBoxItem { Tag: string tag } && double.TryParse(tag, out var value))
        {
            _strokeThickness = value;
            if (_selectedAnnotation is not null)
            {
                _selectedAnnotation.Thickness = value;
                RedrawOverlay();
            }
        }
    }

    // -- Pointer interaction --------------------------------------------------

    private void OnPointerPressed(object sender, PointerRoutedEventArgs e)
    {
        if (_bitmap is null)
        {
            return;
        }

        CommitPendingText();
        var p = e.GetCurrentPoint(OverlayCanvas).Position;

        if (_tool == EditTool.Crop)
        {
            _dragging = true;
            _dragStart = p;
            Canvas.SetLeft(SelectionRect, p.X);
            Canvas.SetTop(SelectionRect, p.Y);
            SelectionRect.Width = 0;
            SelectionRect.Height = 0;
            SelectionRect.Visibility = Visibility.Visible;
            OverlayCanvas.CapturePointer(e.Pointer);
            return;
        }

        if (_tool == EditTool.Select)
        {
            var hit = HitTest(p);
            _selectedAnnotation = hit;
            if (hit is not null)
            {
                _movingAnnotation = hit;
                var origin = PixelToCanvas(new Point(hit.Bounds.X, hit.Bounds.Y));
                _moveOffset = new Point(p.X - origin.X, p.Y - origin.Y);
                OverlayCanvas.CapturePointer(e.Pointer);
            }
            RedrawOverlay();
            return;
        }

        if (_tool == EditTool.Text)
        {
            BeginTextEntry(p);
            return;
        }

        if (_tool == EditTool.Counter)
        {
            var center = CanvasToPixel(p);
            var radius = 18 + _strokeThickness * 2;
            var ann = new Annotation
            {
                Tool = EditTool.Counter,
                Color = _strokeColor,
                Thickness = _strokeThickness,
                Number = _counterValue++,
                Bounds = new Rect(center.X - radius, center.Y - radius, radius * 2, radius * 2),
            };
            _annotations.Add(ann);
            RedrawOverlay();
            return;
        }

        // Shape / line / arrow / pen / redact: begin a drag.
        _dragging = true;
        _dragStart = p;
        var pixel = CanvasToPixel(p);
        _activeAnnotation = new Annotation
        {
            Tool = _tool,
            Color = _strokeColor,
            Thickness = _strokeThickness,
            Bounds = new Rect(pixel.X, pixel.Y, 0, 0),
        };
        if (_tool == EditTool.Pen)
        {
            _activeAnnotation.Points.Add(new Vector2((float)pixel.X, (float)pixel.Y));
        }
        OverlayCanvas.CapturePointer(e.Pointer);
    }

    private void OnPointerMoved(object sender, PointerRoutedEventArgs e)
    {
        var p = e.GetCurrentPoint(OverlayCanvas).Position;

        if (_tool == EditTool.Crop && _dragging)
        {
            var x = Math.Min(p.X, _dragStart.X);
            var y = Math.Min(p.Y, _dragStart.Y);
            Canvas.SetLeft(SelectionRect, x);
            Canvas.SetTop(SelectionRect, y);
            SelectionRect.Width = Math.Abs(p.X - _dragStart.X);
            SelectionRect.Height = Math.Abs(p.Y - _dragStart.Y);
            return;
        }

        if (_tool == EditTool.Select && _movingAnnotation is not null)
        {
            var targetCanvas = new Point(p.X - _moveOffset.X, p.Y - _moveOffset.Y);
            var targetPixel = CanvasToPixel(targetCanvas);
            var b = _movingAnnotation.Bounds;
            var dx = targetPixel.X - b.X;
            var dy = targetPixel.Y - b.Y;
            MoveAnnotation(_movingAnnotation, dx, dy);
            RedrawOverlay();
            return;
        }

        if (_dragging && _activeAnnotation is not null)
        {
            var pixel = CanvasToPixel(p);
            if (_activeAnnotation.Tool == EditTool.Pen)
            {
                _activeAnnotation.Points.Add(new Vector2((float)pixel.X, (float)pixel.Y));
            }

            var startPixel = CanvasToPixel(_dragStart);
            if (_activeAnnotation.Tool is EditTool.Line or EditTool.Arrow)
            {
                // Bounds encode the directed segment start->end.
                _activeAnnotation.Bounds = new Rect(startPixel.X, startPixel.Y, pixel.X - startPixel.X, pixel.Y - startPixel.Y);
            }
            else
            {
                var x = Math.Min(pixel.X, startPixel.X);
                var y = Math.Min(pixel.Y, startPixel.Y);
                _activeAnnotation.Bounds = new Rect(x, y, Math.Abs(pixel.X - startPixel.X), Math.Abs(pixel.Y - startPixel.Y));
            }
            RedrawOverlay(previewActive: true);
        }
    }

    private void OnPointerReleased(object sender, PointerRoutedEventArgs e)
    {
        OverlayCanvas.ReleasePointerCapture(e.Pointer);

        if (_tool == EditTool.Crop && _dragging)
        {
            _dragging = false;
            ApplyCropButton.IsEnabled = SelectionRect.Width > 4 && SelectionRect.Height > 4;
            return;
        }

        if (_tool == EditTool.Select)
        {
            _movingAnnotation = null;
            return;
        }

        if (_dragging && _activeAnnotation is not null)
        {
            _dragging = false;
            var b = _activeAnnotation.Bounds;
            var significant = _activeAnnotation.Tool == EditTool.Pen
                ? _activeAnnotation.Points.Count > 1
                : Math.Abs(b.Width) > 3 || Math.Abs(b.Height) > 3;
            if (significant)
            {
                _annotations.Add(_activeAnnotation);
            }
            _activeAnnotation = null;
            RedrawOverlay();
        }
    }

    private Annotation? HitTest(Point canvasPoint)
    {
        var pixel = CanvasToPixel(canvasPoint);
        for (var i = _annotations.Count - 1; i >= 0; i--)
        {
            var ann = _annotations[i];
            var b = NormalizedBounds(ann);
            var pad = ann.Thickness + 6;
            var inflated = new Rect(b.X - pad, b.Y - pad, b.Width + pad * 2, b.Height + pad * 2);
            if (inflated.Contains(new Point(pixel.X, pixel.Y)))
            {
                return ann;
            }
        }
        return null;
    }

    private static void MoveAnnotation(Annotation ann, double dx, double dy)
    {
        ann.Bounds = new Rect(ann.Bounds.X + dx, ann.Bounds.Y + dy, ann.Bounds.Width, ann.Bounds.Height);
        for (var i = 0; i < ann.Points.Count; i++)
        {
            ann.Points[i] = new Vector2(ann.Points[i].X + (float)dx, ann.Points[i].Y + (float)dy);
        }
    }

    private static Rect NormalizedBounds(Annotation ann)
    {
        var b = ann.Bounds;
        var x = b.Width < 0 ? b.X + b.Width : b.X;
        var y = b.Height < 0 ? b.Y + b.Height : b.Y;
        return new Rect(x, y, Math.Abs(b.Width), Math.Abs(b.Height));
    }

    // -- Text entry -----------------------------------------------------------

    private void BeginTextEntry(Point canvasPoint)
    {
        _pendingTextOrigin = canvasPoint;
        TextEditBox.Text = string.Empty;
        TextEditBox.FontSize = Math.Max(14, _strokeThickness * 3);
        TextEditBox.Foreground = new SolidColorBrush(_strokeColor);
        Canvas.SetLeft(TextEditBox, canvasPoint.X);
        Canvas.SetTop(TextEditBox, canvasPoint.Y);
        TextEditBox.Visibility = Visibility.Visible;
        TextEditBox.Focus(FocusState.Programmatic);
    }

    private void OnTextEntryCommitted(object sender, RoutedEventArgs e) => CommitPendingText();

    private void CommitPendingText()
    {
        if (TextEditBox.Visibility != Visibility.Visible)
        {
            return;
        }

        var text = TextEditBox.Text;
        TextEditBox.Visibility = Visibility.Collapsed;

        if (!string.IsNullOrWhiteSpace(text))
        {
            var pixel = CanvasToPixel(_pendingTextOrigin);
            _annotations.Add(new Annotation
            {
                Tool = EditTool.Text,
                Color = _strokeColor,
                Thickness = _strokeThickness,
                Text = text,
                Bounds = new Rect(pixel.X, pixel.Y, 0, 0),
            });
            RedrawOverlay();
        }
    }

    // -- Keyboard -------------------------------------------------------------

    private void OnRootKeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (TextEditBox.Visibility == Visibility.Visible)
        {
            return;
        }

        var ctrl = Microsoft.UI.Input.InputKeyboardSource
            .GetKeyStateForCurrentThread(Windows.System.VirtualKey.Control)
            .HasFlag(Windows.UI.Core.CoreVirtualKeyStates.Down);

        if (ctrl && e.Key == Windows.System.VirtualKey.Z)
        {
            OnUndo(this, new RoutedEventArgs());
            e.Handled = true;
            return;
        }

        if (e.Key is Windows.System.VirtualKey.Delete or Windows.System.VirtualKey.Back && _selectedAnnotation is not null)
        {
            OnDeleteSelected(this, new RoutedEventArgs());
            e.Handled = true;
            return;
        }

        var tool = e.Key switch
        {
            Windows.System.VirtualKey.V => EditTool.Select,
            Windows.System.VirtualKey.C => EditTool.Crop,
            Windows.System.VirtualKey.R => EditTool.Rectangle,
            Windows.System.VirtualKey.O => EditTool.Ellipse,
            Windows.System.VirtualKey.A => EditTool.Arrow,
            Windows.System.VirtualKey.L => EditTool.Line,
            Windows.System.VirtualKey.D => EditTool.Pen,
            Windows.System.VirtualKey.T => EditTool.Text,
            Windows.System.VirtualKey.N => EditTool.Counter,
            Windows.System.VirtualKey.B => EditTool.Redact,
            _ => (EditTool?)null,
        };
        if (tool is { } t)
        {
            SelectTool(t);
            e.Handled = true;
        }
    }

    private void OnUndo(object sender, RoutedEventArgs e)
    {
        if (_annotations.Count > 0)
        {
            var last = _annotations[^1];
            if (last.Tool == EditTool.Counter)
            {
                _counterValue = Math.Max(1, _counterValue - 1);
            }
            _annotations.RemoveAt(_annotations.Count - 1);
            _selectedAnnotation = null;
            RedrawOverlay();
        }
    }

    private void OnDeleteSelected(object sender, RoutedEventArgs e)
    {
        if (_selectedAnnotation is not null)
        {
            _annotations.Remove(_selectedAnnotation);
            _selectedAnnotation = null;
            RedrawOverlay();
        }
    }

    // -- Coordinate mapping ---------------------------------------------------

    private (double Scale, double OffsetX, double OffsetY) ImageLayout()
    {
        double imgW = _bitmap?.PixelWidth ?? 1;
        double imgH = _bitmap?.PixelHeight ?? 1;
        double hostW = ImageHost.ActualWidth;
        double hostH = ImageHost.ActualHeight;
        if (imgW <= 0 || imgH <= 0 || hostW <= 0 || hostH <= 0)
        {
            return (1, 0, 0);
        }

        var scale = Math.Min(hostW / imgW, hostH / imgH);
        var offsetX = (hostW - imgW * scale) / 2.0;
        var offsetY = (hostH - imgH * scale) / 2.0;
        return (scale, offsetX, offsetY);
    }

    private Point CanvasToPixel(Point canvas)
    {
        var (scale, offX, offY) = ImageLayout();
        if (scale <= 0)
        {
            return canvas;
        }
        return new Point((canvas.X - offX) / scale, (canvas.Y - offY) / scale);
    }

    private Point PixelToCanvas(Point pixel)
    {
        var (scale, offX, offY) = ImageLayout();
        return new Point(pixel.X * scale + offX, pixel.Y * scale + offY);
    }

    private void OnImageHostSizeChanged(object sender, SizeChangedEventArgs e) => RedrawOverlay();

    // -- Live overlay rendering ----------------------------------------------

    private void RedrawOverlay(bool previewActive = false)
    {
        // Remove all annotation visuals but keep SelectionRect and TextEditBox.
        for (var i = OverlayCanvas.Children.Count - 1; i >= 0; i--)
        {
            var child = OverlayCanvas.Children[i];
            if (child != SelectionRect && child != TextEditBox)
            {
                OverlayCanvas.Children.RemoveAt(i);
            }
        }

        if (_bitmap is null)
        {
            return;
        }

        foreach (var ann in _annotations)
        {
            DrawAnnotationPreview(ann, ann == _selectedAnnotation);
        }

        if (previewActive && _activeAnnotation is not null)
        {
            DrawAnnotationPreview(_activeAnnotation, false);
        }
    }

    private void DrawAnnotationPreview(Annotation ann, bool selected)
    {
        var (scale, _, _) = ImageLayout();
        var brush = new SolidColorBrush(ann.Color);
        var thickness = Math.Max(1, ann.Thickness * scale);

        switch (ann.Tool)
        {
            case EditTool.Rectangle:
            {
                var b = NormalizedBounds(ann);
                var tl = PixelToCanvas(new Point(b.X, b.Y));
                var rect = new Rectangle
                {
                    Width = b.Width * scale,
                    Height = b.Height * scale,
                    Stroke = brush,
                    StrokeThickness = thickness,
                };
                Canvas.SetLeft(rect, tl.X);
                Canvas.SetTop(rect, tl.Y);
                OverlayCanvas.Children.Add(rect);
                break;
            }
            case EditTool.Ellipse:
            {
                var b = NormalizedBounds(ann);
                var tl = PixelToCanvas(new Point(b.X, b.Y));
                var ellipse = new Ellipse
                {
                    Width = b.Width * scale,
                    Height = b.Height * scale,
                    Stroke = brush,
                    StrokeThickness = thickness,
                };
                Canvas.SetLeft(ellipse, tl.X);
                Canvas.SetTop(ellipse, tl.Y);
                OverlayCanvas.Children.Add(ellipse);
                break;
            }
            case EditTool.Line:
            {
                var start = PixelToCanvas(new Point(ann.Bounds.X, ann.Bounds.Y));
                var end = PixelToCanvas(new Point(ann.Bounds.X + ann.Bounds.Width, ann.Bounds.Y + ann.Bounds.Height));
                OverlayCanvas.Children.Add(new Line
                {
                    X1 = start.X,
                    Y1 = start.Y,
                    X2 = end.X,
                    Y2 = end.Y,
                    Stroke = brush,
                    StrokeThickness = thickness,
                    StrokeStartLineCap = PenLineCap.Round,
                    StrokeEndLineCap = PenLineCap.Round,
                });
                break;
            }
            case EditTool.Arrow:
            {
                var start = PixelToCanvas(new Point(ann.Bounds.X, ann.Bounds.Y));
                var end = PixelToCanvas(new Point(ann.Bounds.X + ann.Bounds.Width, ann.Bounds.Y + ann.Bounds.Height));
                AddArrowShapes(start, end, brush, thickness);
                break;
            }
            case EditTool.Pen:
            {
                if (ann.Points.Count > 1)
                {
                    var poly = new Polyline
                    {
                        Stroke = brush,
                        StrokeThickness = thickness,
                        StrokeLineJoin = PenLineJoin.Round,
                        StrokeStartLineCap = PenLineCap.Round,
                        StrokeEndLineCap = PenLineCap.Round,
                    };
                    foreach (var pt in ann.Points)
                    {
                        var c = PixelToCanvas(new Point(pt.X, pt.Y));
                        poly.Points.Add(c);
                    }
                    OverlayCanvas.Children.Add(poly);
                }
                break;
            }
            case EditTool.Redact:
            {
                var b = NormalizedBounds(ann);
                var tl = PixelToCanvas(new Point(b.X, b.Y));
                var rect = new Rectangle
                {
                    Width = b.Width * scale,
                    Height = b.Height * scale,
                    Fill = new SolidColorBrush(Color.FromArgb(235, 30, 30, 30)),
                    RadiusX = 4,
                    RadiusY = 4,
                };
                Canvas.SetLeft(rect, tl.X);
                Canvas.SetTop(rect, tl.Y);
                OverlayCanvas.Children.Add(rect);
                break;
            }
            case EditTool.Text:
            {
                var tl = PixelToCanvas(new Point(ann.Bounds.X, ann.Bounds.Y));
                var text = new TextBlock
                {
                    Text = ann.Text,
                    Foreground = brush,
                    FontSize = Math.Max(14, ann.Thickness * 3) * scale,
                    FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
                };
                Canvas.SetLeft(text, tl.X);
                Canvas.SetTop(text, tl.Y);
                OverlayCanvas.Children.Add(text);
                break;
            }
            case EditTool.Counter:
            {
                var b = NormalizedBounds(ann);
                var tl = PixelToCanvas(new Point(b.X, b.Y));
                var diameter = b.Width * scale;
                var grid = new Grid
                {
                    Width = diameter,
                    Height = diameter,
                };
                grid.Children.Add(new Ellipse { Fill = brush });
                grid.Children.Add(new TextBlock
                {
                    Text = ann.Number.ToString(),
                    Foreground = new SolidColorBrush(Colors.White),
                    FontWeight = Microsoft.UI.Text.FontWeights.Bold,
                    FontSize = diameter * 0.5,
                    HorizontalAlignment = HorizontalAlignment.Center,
                    VerticalAlignment = VerticalAlignment.Center,
                });
                Canvas.SetLeft(grid, tl.X);
                Canvas.SetTop(grid, tl.Y);
                OverlayCanvas.Children.Add(grid);
                break;
            }
        }

        if (selected)
        {
            var b = NormalizedBounds(ann);
            var tl = PixelToCanvas(new Point(b.X, b.Y));
            var marquee = new Rectangle
            {
                Width = Math.Max(b.Width * scale, 8) + 12,
                Height = Math.Max(b.Height * scale, 8) + 12,
                Stroke = new SolidColorBrush(Colors.DeepSkyBlue),
                StrokeThickness = 1.5,
                StrokeDashArray = new DoubleCollection { 4, 2 },
            };
            Canvas.SetLeft(marquee, tl.X - 6);
            Canvas.SetTop(marquee, tl.Y - 6);
            OverlayCanvas.Children.Add(marquee);
        }
    }

    private void AddArrowShapes(Point start, Point end, Brush brush, double thickness)
    {
        OverlayCanvas.Children.Add(new Line
        {
            X1 = start.X,
            Y1 = start.Y,
            X2 = end.X,
            Y2 = end.Y,
            Stroke = brush,
            StrokeThickness = thickness,
            StrokeStartLineCap = PenLineCap.Round,
            StrokeEndLineCap = PenLineCap.Round,
        });

        var angle = Math.Atan2(end.Y - start.Y, end.X - start.X);
        var headLen = Math.Max(12, thickness * 3.5);
        const double spread = Math.PI / 7;
        var p1 = new Point(end.X - headLen * Math.Cos(angle - spread), end.Y - headLen * Math.Sin(angle - spread));
        var p2 = new Point(end.X - headLen * Math.Cos(angle + spread), end.Y - headLen * Math.Sin(angle + spread));
        var head = new Polygon { Fill = brush };
        head.Points.Add(end);
        head.Points.Add(p1);
        head.Points.Add(p2);
        OverlayCanvas.Children.Add(head);
    }

    // -- Crop -----------------------------------------------------------------

    private void ClearSelection()
    {
        SelectionRect.Visibility = Visibility.Collapsed;
        SelectionRect.Width = 0;
        SelectionRect.Height = 0;
        ApplyCropButton.IsEnabled = false;
    }

    private async void OnApplyCrop(object sender, RoutedEventArgs e)
    {
        if (_bitmap is null || SelectionRect.Visibility != Visibility.Visible)
        {
            return;
        }

        var bounds = MapSelectionToPixels();
        if (bounds is not { } rect || rect.Width < 1 || rect.Height < 1)
        {
            return;
        }

        try
        {
            // Bake annotations first so they crop with the image, then crop.
            var flattened = await RenderToBitmapAsync();
            var cropped = await CropAsync(flattened, rect);
            flattened.Dispose();
            await SetBitmapAsync(cropped);
            _annotations.Clear();
            _counterValue = 1;
            RedrawOverlay();
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"Crop failed: {ex}");
        }
    }

    private BitmapBounds? MapSelectionToPixels()
    {
        if (_bitmap is null)
        {
            return null;
        }

        double imgW = _bitmap.PixelWidth;
        double imgH = _bitmap.PixelHeight;
        var (scale, offsetX, offsetY) = ImageLayout();
        if (scale <= 0)
        {
            return null;
        }

        var selLeft = Canvas.GetLeft(SelectionRect);
        var selTop = Canvas.GetTop(SelectionRect);

        var pxLeft = Math.Clamp((selLeft - offsetX) / scale, 0, imgW);
        var pxTop = Math.Clamp((selTop - offsetY) / scale, 0, imgH);
        var pxRight = Math.Clamp((selLeft + SelectionRect.Width - offsetX) / scale, 0, imgW);
        var pxBottom = Math.Clamp((selTop + SelectionRect.Height - offsetY) / scale, 0, imgH);

        return new BitmapBounds
        {
            X = (uint)Math.Round(pxLeft),
            Y = (uint)Math.Round(pxTop),
            Width = (uint)Math.Round(pxRight - pxLeft),
            Height = (uint)Math.Round(pxBottom - pxTop),
        };
    }

    private static async Task<SoftwareBitmap> CropAsync(SoftwareBitmap source, BitmapBounds bounds)
    {
        using var stream = new InMemoryRandomAccessStream();
        var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.PngEncoderId, stream);
        encoder.SetSoftwareBitmap(source);
        await encoder.FlushAsync();

        stream.Seek(0);
        var decoder = await BitmapDecoder.CreateAsync(stream);
        var transform = new BitmapTransform { Bounds = bounds };
        return await decoder.GetSoftwareBitmapAsync(
            BitmapPixelFormat.Bgra8,
            BitmapAlphaMode.Premultiplied,
            transform,
            ExifOrientationMode.IgnoreExifOrientation,
            ColorManagementMode.DoNotColorManage);
    }

    private void OnReset(object sender, RoutedEventArgs e) => _ = LoadAsync();

    // -- Win2D baking of annotations -----------------------------------------

    /// <summary>
    /// Flattens the current bitmap plus all annotations into a new <see cref="SoftwareBitmap"/>
    /// at full resolution using Win2D. Returns a copy even when there are no annotations.
    /// </summary>
    private async Task<SoftwareBitmap> RenderToBitmapAsync()
    {
        if (_bitmap is null)
        {
            throw new InvalidOperationException("No bitmap loaded.");
        }

        await Task.CompletedTask;
        var device = CanvasDevice.GetSharedDevice();
        using var source = CanvasBitmap.CreateFromSoftwareBitmap(device, _bitmap);
        var width = (float)_bitmap.PixelWidth;
        var height = (float)_bitmap.PixelHeight;

        using var target = new CanvasRenderTarget(device, width, height, 96);
        using (var ds = target.CreateDrawingSession())
        {
            ds.Clear(Colors.Transparent);

            // Redactions sample the underlying image, so draw the base first, then redactions,
            // then the rest of the annotations on top.
            ds.DrawImage(source);

            foreach (var ann in _annotations.Where(a => a.Tool == EditTool.Redact))
            {
                DrawRedaction(ds, source, ann);
            }

            foreach (var ann in _annotations.Where(a => a.Tool != EditTool.Redact))
            {
                DrawAnnotationToSession(ds, ann);
            }
        }

        return SoftwareBitmap.CreateCopyFromBuffer(
            target.GetPixelBytes().AsBuffer(),
            BitmapPixelFormat.Bgra8,
            (int)width,
            (int)height,
            BitmapAlphaMode.Premultiplied);
    }

    private static void DrawRedaction(CanvasDrawingSession ds, CanvasBitmap source, Annotation ann)
    {
        var b = NormalizedBounds(ann);
        if (b.Width < 1 || b.Height < 1)
        {
            return;
        }

        var rect = new Rect(b.X, b.Y, b.Width, b.Height);
        using var crop = new CropEffect { Source = source, SourceRectangle = rect };

        // Pixelate: shrink to chunky blocks then scale back up with nearest-neighbor.
        var block = (float)Math.Max(0.04, 1.0 / Math.Max(8, b.Width / 16));
        using var down = new ScaleEffect
        {
            Source = crop,
            Scale = new Vector2(block, block),
            InterpolationMode = CanvasImageInterpolation.NearestNeighbor,
        };
        using var up = new ScaleEffect
        {
            Source = down,
            Scale = new Vector2(1f / block, 1f / block),
            InterpolationMode = CanvasImageInterpolation.NearestNeighbor,
        };
        ds.DrawImage(up, rect, rect);
    }

    private void DrawAnnotationToSession(CanvasDrawingSession ds, Annotation ann)
    {
        var color = ann.Color;
        var thickness = (float)ann.Thickness;

        switch (ann.Tool)
        {
            case EditTool.Rectangle:
            {
                var b = NormalizedBounds(ann);
                ds.DrawRectangle((float)b.X, (float)b.Y, (float)b.Width, (float)b.Height, color, thickness);
                break;
            }
            case EditTool.Ellipse:
            {
                var b = NormalizedBounds(ann);
                ds.DrawEllipse(
                    (float)(b.X + b.Width / 2),
                    (float)(b.Y + b.Height / 2),
                    (float)(b.Width / 2),
                    (float)(b.Height / 2),
                    color,
                    thickness);
                break;
            }
            case EditTool.Line:
            {
                ds.DrawLine(
                    new Vector2((float)ann.Bounds.X, (float)ann.Bounds.Y),
                    new Vector2((float)(ann.Bounds.X + ann.Bounds.Width), (float)(ann.Bounds.Y + ann.Bounds.Height)),
                    color,
                    thickness,
                    new CanvasStrokeStyle { StartCap = CanvasCapStyle.Round, EndCap = CanvasCapStyle.Round });
                break;
            }
            case EditTool.Arrow:
            {
                DrawArrowToSession(ds, ann, color, thickness);
                break;
            }
            case EditTool.Pen:
            {
                if (ann.Points.Count > 1)
                {
                    var style = new CanvasStrokeStyle
                    {
                        StartCap = CanvasCapStyle.Round,
                        EndCap = CanvasCapStyle.Round,
                        LineJoin = CanvasLineJoin.Round,
                    };
                    for (var i = 1; i < ann.Points.Count; i++)
                    {
                        ds.DrawLine(ann.Points[i - 1], ann.Points[i], color, thickness, style);
                    }
                }
                break;
            }
            case EditTool.Text:
            {
                var fontSize = (float)Math.Max(14, ann.Thickness * 3);
                using var format = new CanvasTextFormat
                {
                    FontSize = fontSize,
                    FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
                };
                ds.DrawText(ann.Text, new Vector2((float)ann.Bounds.X, (float)ann.Bounds.Y), color, format);
                break;
            }
            case EditTool.Counter:
            {
                var b = NormalizedBounds(ann);
                var cx = (float)(b.X + b.Width / 2);
                var cy = (float)(b.Y + b.Height / 2);
                var radius = (float)(b.Width / 2);
                ds.FillCircle(cx, cy, radius, color);
                var fontSize = radius;
                using var format = new CanvasTextFormat
                {
                    FontSize = fontSize,
                    FontWeight = Microsoft.UI.Text.FontWeights.Bold,
                    HorizontalAlignment = CanvasHorizontalAlignment.Center,
                    VerticalAlignment = CanvasVerticalAlignment.Center,
                };
                ds.DrawText(ann.Number.ToString(), new Rect(b.X, b.Y, b.Width, b.Height), Colors.White, format);
                break;
            }
        }
    }

    private static void DrawArrowToSession(CanvasDrawingSession ds, Annotation ann, Color color, float thickness)
    {
        var start = new Vector2((float)ann.Bounds.X, (float)ann.Bounds.Y);
        var end = new Vector2((float)(ann.Bounds.X + ann.Bounds.Width), (float)(ann.Bounds.Y + ann.Bounds.Height));
        var style = new CanvasStrokeStyle { StartCap = CanvasCapStyle.Round, EndCap = CanvasCapStyle.Round };
        ds.DrawLine(start, end, color, thickness, style);

        var angle = Math.Atan2(end.Y - start.Y, end.X - start.X);
        var headLen = Math.Max(12, thickness * 3.5);
        const double spread = Math.PI / 7;
        var p1 = new Vector2(
            (float)(end.X - headLen * Math.Cos(angle - spread)),
            (float)(end.Y - headLen * Math.Sin(angle - spread)));
        var p2 = new Vector2(
            (float)(end.X - headLen * Math.Cos(angle + spread)),
            (float)(end.Y - headLen * Math.Sin(angle + spread)));
        using var head = CanvasGeometry.CreatePolygon(ds.Device, new[] { end, p1, p2 });
        ds.FillGeometry(head, color);
    }

    // -- Output ---------------------------------------------------------------

    private async void OnSave(object sender, RoutedEventArgs e)
    {
        if (_bitmap is null)
        {
            return;
        }

        CommitPendingText();
        await EncodeToFileAsync(_filePath);
        Close();
    }

    private async void OnSaveCopy(object sender, RoutedEventArgs e)
    {
        if (_bitmap is null)
        {
            return;
        }

        CommitPendingText();
        var picker = new FileSavePicker { SuggestedStartLocation = PickerLocationId.PicturesLibrary };
        picker.FileTypeChoices.Add("PNG image", new[] { ".png" });
        picker.FileTypeChoices.Add("JPEG image", new[] { ".jpg" });
        picker.SuggestedFileName = System.IO.Path.GetFileNameWithoutExtension(_filePath) + " (edited)";

        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        WinRT.Interop.InitializeWithWindow.Initialize(picker, hwnd);

        var file = await picker.PickSaveFileAsync();
        if (file is not null)
        {
            await EncodeToFileAsync(file.Path);
        }
    }

    private async void OnCopy(object sender, RoutedEventArgs e)
    {
        if (_bitmap is null)
        {
            return;
        }

        try
        {
            CommitPendingText();
            using var flattened = await RenderToBitmapAsync();
            using var stream = new InMemoryRandomAccessStream();
            var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.PngEncoderId, stream);
            encoder.SetSoftwareBitmap(flattened);
            await encoder.FlushAsync();

            var package = new DataPackage { RequestedOperation = DataPackageOperation.Copy };
            package.SetBitmap(RandomAccessStreamReference.CreateFromStream(stream));
            Clipboard.SetContent(package);
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"Copy failed: {ex}");
        }
    }

    private async Task EncodeToFileAsync(string path)
    {
        if (_bitmap is null)
        {
            return;
        }

        try
        {
            using var flattened = await RenderToBitmapAsync();
            var isPng = path.EndsWith(".png", StringComparison.OrdinalIgnoreCase);
            var encoderId = isPng ? BitmapEncoder.PngEncoderId : BitmapEncoder.JpegEncoderId;

            var folder = await StorageFolder.GetFolderFromPathAsync(System.IO.Path.GetDirectoryName(path)!);
            var file = await folder.CreateFileAsync(System.IO.Path.GetFileName(path), CreationCollisionOption.ReplaceExisting);
            using var stream = await file.OpenAsync(FileAccessMode.ReadWrite);
            var encoder = await BitmapEncoder.CreateAsync(encoderId, stream);

            SoftwareBitmap toEncode = flattened;
            SoftwareBitmap? converted = null;
            if (!isPng && flattened.BitmapAlphaMode != BitmapAlphaMode.Ignore)
            {
                converted = SoftwareBitmap.Convert(flattened, BitmapPixelFormat.Bgra8, BitmapAlphaMode.Ignore);
                toEncode = converted;
            }

            encoder.SetSoftwareBitmap(toEncode);
            await encoder.FlushAsync();
            converted?.Dispose();
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"Save failed: {ex}");
        }
    }
}
