using System;
using System.Collections.Generic;
using System.Linq;
using System.Numerics;
using System.Runtime.InteropServices.WindowsRuntime;
using System.Threading.Tasks;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Graphics.Canvas;
using Microsoft.Graphics.Canvas.Brushes;
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

    private enum RedactionLevel
    {
        Light,
        Medium,
        Heavy,
    }

    private sealed class Annotation
    {
        public EditTool Tool { get; set; }
        public Rect Bounds { get; set; }
        public Color Color { get; set; }
        public double Thickness { get; set; }
        public string Text { get; set; } = string.Empty;
        public int Number { get; set; }
        public double SizeScale { get; set; } = 1.0;
        public RedactionLevel Redaction { get; set; } = RedactionLevel.Medium;
        public List<Vector2> Points { get; } = new();

        // Cached blurred preview for redaction annotations (invalidated on move / level change).
        public SoftwareBitmapSource? RedactPreview { get; set; }
        public Rect RedactPreviewBounds { get; set; }
        public RedactionLevel RedactPreviewLevel { get; set; }
    }

    private readonly string _filePath;
    private SoftwareBitmap? _bitmap;
    private CanvasBitmap? _canvasSource;

    private readonly List<Annotation> _annotations = new();
    private Annotation? _activeAnnotation;
    private Annotation? _selectedAnnotation;
    private EditTool _tool = EditTool.Crop;
    private Color _strokeColor = Colors.Red;
    private double _strokeThickness = 6;
    private double _numberScale = 1.0;
    private RedactionLevel _redactionLevel = RedactionLevel.Medium;
    private int _counterValue = 1;

    private bool _dragging;
    private Point _dragStart;
    private Annotation? _movingAnnotation;
    private Point _moveOffset;
    private Point _pendingTextOrigin;
    private bool _textBoxFocused;

    // -- Export background / padding ------------------------------------------

    private enum ExportBackgroundStyle
    {
        Transparent,
        Solid,
        Gradient,
    }

    private sealed record BackgroundPreset(string Id, string Label, ExportBackgroundStyle Style, Color Primary, Color? Secondary);

    private ExportBackgroundStyle _bgStyle = ExportBackgroundStyle.Transparent;
    private Color _bgColor = Color.FromArgb(255, 245, 245, 250);
    private Color _bgColor2 = Color.FromArgb(255, 214, 230, 252);
    private double _canvasPadding;
    private double _canvasCornerRadius;
    private double _canvasShadow;
    private bool _bgInitializing;

    private static readonly BackgroundPreset[] SolidPresets =
    {
        new("white", "White", ExportBackgroundStyle.Solid, Color.FromArgb(255, 255, 255, 255), null),
        new("ink", "Ink", ExportBackgroundStyle.Solid, Color.FromArgb(255, 20, 23, 26), null),
        new("coral", "Coral", ExportBackgroundStyle.Solid, Color.FromArgb(255, 255, 122, 107), null),
        new("lemon", "Lemon", ExportBackgroundStyle.Solid, Color.FromArgb(255, 255, 224, 64), null),
        new("mint", "Mint", ExportBackgroundStyle.Solid, Color.FromArgb(255, 105, 219, 158), null),
        new("sky", "Sky", ExportBackgroundStyle.Solid, Color.FromArgb(255, 87, 171, 245), null),
        new("lilac", "Lilac", ExportBackgroundStyle.Solid, Color.FromArgb(255, 179, 148, 240), null),
        new("bubblegum", "Bubblegum", ExportBackgroundStyle.Solid, Color.FromArgb(255, 255, 107, 194), null),
        new("tangerine", "Tangerine", ExportBackgroundStyle.Solid, Color.FromArgb(255, 255, 143, 41), null),
        new("lagoon", "Lagoon", ExportBackgroundStyle.Solid, Color.FromArgb(255, 0, 184, 199), null),
        new("plum", "Plum", ExportBackgroundStyle.Solid, Color.FromArgb(255, 99, 46, 148), null),
        new("slate", "Slate", ExportBackgroundStyle.Solid, Color.FromArgb(255, 86, 101, 115), null),
    };

    private static readonly BackgroundPreset[] GradientPresets =
    {
        new("sunset", "Sunset", ExportBackgroundStyle.Gradient, Color.FromArgb(255, 255, 122, 94), Color.FromArgb(255, 255, 219, 79)),
        new("ocean", "Ocean", ExportBackgroundStyle.Gradient, Color.FromArgb(255, 38, 135, 232), Color.FromArgb(255, 46, 224, 191)),
        new("candy", "Candy", ExportBackgroundStyle.Gradient, Color.FromArgb(255, 255, 107, 173), Color.FromArgb(255, 140, 199, 255)),
        new("forest", "Forest", ExportBackgroundStyle.Gradient, Color.FromArgb(255, 41, 143, 89), Color.FromArgb(255, 184, 224, 107)),
        new("ember", "Ember", ExportBackgroundStyle.Gradient, Color.FromArgb(255, 56, 20, 13), Color.FromArgb(255, 255, 115, 41)),
        new("aurora", "Aurora", ExportBackgroundStyle.Gradient, Color.FromArgb(255, 71, 240, 184), Color.FromArgb(255, 133, 107, 255)),
        new("peach", "Peach", ExportBackgroundStyle.Gradient, Color.FromArgb(255, 255, 184, 133), Color.FromArgb(255, 250, 107, 138)),
        new("glacier", "Glacier", ExportBackgroundStyle.Gradient, Color.FromArgb(255, 186, 240, 255), Color.FromArgb(255, 107, 148, 245)),
        new("neon", "Neon", ExportBackgroundStyle.Gradient, Color.FromArgb(255, 13, 255, 138), Color.FromArgb(255, 255, 20, 179)),
        new("mango", "Mango", ExportBackgroundStyle.Gradient, Color.FromArgb(255, 255, 199, 51), Color.FromArgb(255, 255, 66, 46)),
        new("midnight", "Midnight", ExportBackgroundStyle.Gradient, Color.FromArgb(255, 13, 18, 46), Color.FromArgb(255, 0, 148, 209)),
        new("prism", "Prism", ExportBackgroundStyle.Gradient, Color.FromArgb(255, 250, 41, 97), Color.FromArgb(255, 46, 219, 237)),
    };

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
        ThicknessCombo.SelectedIndex = 3;
        NumberSizeCombo.SelectedIndex = 2;
        RedactionCombo.SelectedIndex = 1;
        SelectTool(EditTool.Crop);

        InitializeBackgroundControls();

        RootGrid.KeyDown += OnRootKeyDown;

        _ = LoadAsync();
    }

    private void InitializeBackgroundControls()
    {
        _bgInitializing = true;

        foreach (var preset in SolidPresets)
        {
            SolidPresetGrid.Items.Add(CreatePresetSwatch(preset));
        }

        foreach (var preset in GradientPresets)
        {
            GradientPresetGrid.Items.Add(CreatePresetSwatch(preset));
        }

        BgStyleCombo.SelectedIndex = 0;
        BgColorPicker.Color = _bgColor;
        PaddingSlider.Value = _canvasPadding;
        CornerSlider.Value = _canvasCornerRadius;
        ShadowSlider.Value = _canvasShadow;
        UpdateSliderHeaders();
        UpdateBackgroundStyleUi();
        ImageCard.Shadow = new ThemeShadow();

        _bgInitializing = false;
    }

    private Button CreatePresetSwatch(BackgroundPreset preset)
    {
        Brush fill = preset.Style == ExportBackgroundStyle.Gradient && preset.Secondary is { } secondary
            ? new LinearGradientBrush
            {
                StartPoint = new Point(0, 0),
                EndPoint = new Point(1, 1),
                GradientStops =
                {
                    new GradientStop { Color = preset.Primary, Offset = 0 },
                    new GradientStop { Color = secondary, Offset = 1 },
                },
            }
            : new SolidColorBrush(preset.Primary);

        var button = new Button
        {
            Width = 30,
            Height = 30,
            Padding = new Thickness(0),
            Margin = new Thickness(0),
            CornerRadius = new CornerRadius(6),
            Background = fill,
            BorderThickness = new Thickness(1),
            BorderBrush = new SolidColorBrush(Color.FromArgb(40, 0, 0, 0)),
            Tag = preset,
        };
        ToolTipService.SetToolTip(button, preset.Label);
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(button, $"{preset.Label} background");
        button.Click += OnPresetSwatchClick;
        return button;
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

        _canvasSource?.Dispose();
        _canvasSource = CanvasBitmap.CreateFromSoftwareBitmap(CanvasDevice.GetSharedDevice(), bitmap);

        var source = new SoftwareBitmapSource();
        await source.SetBitmapAsync(bitmap);
        PreviewImage.Source = source;

        ClearSelection();
        LayoutCanvas();
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
        var showsStroke = tool is EditTool.Rectangle or EditTool.Ellipse or EditTool.Arrow
            or EditTool.Line or EditTool.Pen or EditTool.Text;
        var showsNumber = tool is EditTool.Counter;
        var showsRedact = tool is EditTool.Redact;

        ThicknessCombo.Visibility = showsStroke ? Visibility.Visible : Visibility.Collapsed;
        NumberSizeCombo.Visibility = showsNumber ? Visibility.Visible : Visibility.Collapsed;
        RedactionCombo.Visibility = showsRedact ? Visibility.Visible : Visibility.Collapsed;
        // Redaction has no color; everything else that annotates picks a color.
        ColorButton.Visibility = (annotating && !showsRedact) ? Visibility.Visible : Visibility.Collapsed;

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

    private void OnNumberSizeChanged(object sender, SelectionChangedEventArgs e)
    {
        if (NumberSizeCombo.SelectedItem is ComboBoxItem { Tag: string tag } && double.TryParse(tag, out var value))
        {
            _numberScale = value;
            if (_selectedAnnotation is { Tool: EditTool.Counter } ann)
            {
                ann.SizeScale = value;
                var center = new Point(ann.Bounds.X + ann.Bounds.Width / 2, ann.Bounds.Y + ann.Bounds.Height / 2);
                var radius = CounterRadius(value);
                ann.Bounds = new Rect(center.X - radius, center.Y - radius, radius * 2, radius * 2);
                RedrawOverlay();
            }
        }
    }

    private void OnRedactionLevelChanged(object sender, SelectionChangedEventArgs e)
    {
        if (RedactionCombo.SelectedItem is ComboBoxItem { Tag: string tag }
            && Enum.TryParse<RedactionLevel>(tag, out var level))
        {
            _redactionLevel = level;
            if (_selectedAnnotation is { Tool: EditTool.Redact } ann)
            {
                ann.Redaction = level;
                ann.RedactPreview = null;
                RedrawOverlay();
            }
        }
    }

    private double CounterRadius(double scale) => Math.Max(12, 22 * scale);

    // -- Export background handlers -------------------------------------------

    private void OnPresetSwatchClick(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: BackgroundPreset preset })
        {
            _bgStyle = preset.Style;
            _bgColor = preset.Primary;
            _bgColor2 = preset.Secondary ?? preset.Primary;

            _bgInitializing = true;
            BgStyleCombo.SelectedIndex = preset.Style == ExportBackgroundStyle.Gradient ? 2 : 1;
            BgColorPicker.Color = _bgColor;
            _bgInitializing = false;

            UpdateBackgroundStyleUi();
            LayoutCanvas();
        }
    }

    private void OnBgStyleChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_bgInitializing)
        {
            return;
        }

        _bgStyle = BgStyleCombo.SelectedIndex switch
        {
            1 => ExportBackgroundStyle.Solid,
            2 => ExportBackgroundStyle.Gradient,
            _ => ExportBackgroundStyle.Transparent,
        };
        UpdateBackgroundStyleUi();
        LayoutCanvas();
    }

    private void UpdateBackgroundStyleUi()
    {
        SolidPresetGrid.Visibility = _bgStyle == ExportBackgroundStyle.Solid ? Visibility.Visible : Visibility.Collapsed;
        GradientPresetGrid.Visibility = _bgStyle == ExportBackgroundStyle.Gradient ? Visibility.Visible : Visibility.Collapsed;
        CustomColorPanel.Visibility = _bgStyle == ExportBackgroundStyle.Solid ? Visibility.Visible : Visibility.Collapsed;
    }

    private void OnBgCustomColorChanged(ColorPicker sender, ColorChangedEventArgs args)
    {
        if (_bgInitializing)
        {
            return;
        }

        _bgColor = args.NewColor;
        if (_bgStyle == ExportBackgroundStyle.Solid)
        {
            LayoutCanvas();
        }
    }

    private void OnApplyCustomSolidBackground(object sender, RoutedEventArgs e)
    {
        _bgStyle = ExportBackgroundStyle.Solid;
        _bgColor = BgColorPicker.Color;

        _bgInitializing = true;
        BgStyleCombo.SelectedIndex = 1;
        _bgInitializing = false;

        UpdateBackgroundStyleUi();
        LayoutCanvas();
    }

    private void OnPaddingChanged(object sender, RangeBaseValueChangedEventArgs e)
    {
        if (_bgInitializing)
        {
            return;
        }

        _canvasPadding = e.NewValue;
        UpdateSliderHeaders();
        LayoutCanvas();
        RedrawOverlay();
    }

    private void OnCornerChanged(object sender, RangeBaseValueChangedEventArgs e)
    {
        if (_bgInitializing)
        {
            return;
        }

        _canvasCornerRadius = e.NewValue;
        UpdateSliderHeaders();
        LayoutCanvas();
    }

    private void OnShadowChanged(object sender, RangeBaseValueChangedEventArgs e)
    {
        if (_bgInitializing)
        {
            return;
        }

        _canvasShadow = e.NewValue;
        UpdateSliderHeaders();
        LayoutCanvas();
    }

    private void UpdateSliderHeaders()
    {
        PaddingSlider.Header = $"Padding — {(int)_canvasPadding} px";
        CornerSlider.Header = $"Corners — {(int)_canvasCornerRadius} px";
        ShadowSlider.Header = $"Shadow — {(int)_canvasShadow}";
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
            var radius = CounterRadius(_numberScale);
            var ann = new Annotation
            {
                Tool = EditTool.Counter,
                Color = _strokeColor,
                Thickness = _strokeThickness,
                SizeScale = _numberScale,
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
            Redaction = _redactionLevel,
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
        _textBoxFocused = false;
        TextEditBox.Text = string.Empty;
        TextEditBox.FontSize = Math.Max(14, _strokeThickness * 3);
        TextEditBox.Foreground = new SolidColorBrush(_strokeColor);
        Canvas.SetLeft(TextEditBox, canvasPoint.X);
        Canvas.SetTop(TextEditBox, canvasPoint.Y);
        TextEditBox.Visibility = Visibility.Visible;

        // Focus must be deferred: setting focus synchronously inside the pointer-pressed
        // handler is overridden when the pointer is released, which immediately fires
        // LostFocus and dismisses the box ("clicks and goes away").
        DispatcherQueue.TryEnqueue(() =>
        {
            if (TextEditBox.Visibility == Visibility.Visible)
            {
                TextEditBox.Focus(FocusState.Programmatic);
            }
        });
    }

    private void OnTextEntryGotFocus(object sender, RoutedEventArgs e) => _textBoxFocused = true;

    private void OnTextEntryKeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key == Windows.System.VirtualKey.Enter)
        {
            e.Handled = true;
            CommitPendingText();
        }
        else if (e.Key == Windows.System.VirtualKey.Escape)
        {
            e.Handled = true;
            _textBoxFocused = false;
            TextEditBox.Text = string.Empty;
            TextEditBox.Visibility = Visibility.Collapsed;
        }
    }

    private void OnTextEntryCommitted(object sender, RoutedEventArgs e)
    {
        // Ignore the transient LostFocus that fires before the box has actually gained
        // focus (the deferred Focus() call races with pointer release).
        if (!_textBoxFocused)
        {
            return;
        }

        CommitPendingText();
    }

    private void CommitPendingText()
    {
        if (TextEditBox.Visibility != Visibility.Visible)
        {
            return;
        }

        var text = TextEditBox.Text;
        _textBoxFocused = false;
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

        // The composite (background frame) is the image plus padding on every side.
        var pad = _canvasPadding;
        var compW = imgW + pad * 2;
        var compH = imgH + pad * 2;
        var scale = Math.Min(hostW / compW, hostH / compH);
        var frameOffsetX = (hostW - compW * scale) / 2.0;
        var frameOffsetY = (hostH - compH * scale) / 2.0;
        // Offsets returned are the image card's top-left (inside the padded frame),
        // so annotation pixel<->canvas mapping stays aligned with the screenshot.
        var offsetX = frameOffsetX + pad * scale;
        var offsetY = frameOffsetY + pad * scale;
        return (scale, offsetX, offsetY);
    }

    private void LayoutCanvas()
    {
        if (_bitmap is null)
        {
            return;
        }

        double imgW = _bitmap.PixelWidth;
        double imgH = _bitmap.PixelHeight;
        var (scale, imageOffX, imageOffY) = ImageLayout();
        var pad = _canvasPadding * scale;

        // Background frame spans image + padding on all sides.
        Canvas.SetLeft(CanvasBackground, imageOffX - pad);
        Canvas.SetTop(CanvasBackground, imageOffY - pad);
        CanvasBackground.Width = imgW * scale + pad * 2;
        CanvasBackground.Height = imgH * scale + pad * 2;
        CanvasBackground.CornerRadius = new CornerRadius(0);
        CanvasBackground.Background = _bgStyle == ExportBackgroundStyle.Transparent ? null : MakeBackgroundBrush();
        CanvasBackground.Visibility = _bgStyle == ExportBackgroundStyle.Transparent
            ? Visibility.Collapsed
            : Visibility.Visible;

        // Image card sits inside the frame, rounded + elevated to match export.
        Canvas.SetLeft(ImageCard, imageOffX);
        Canvas.SetTop(ImageCard, imageOffY);
        ImageCard.Width = imgW * scale;
        ImageCard.Height = imgH * scale;
        ImageCard.CornerRadius = new CornerRadius(_canvasCornerRadius * scale);
        ImageCard.Translation = new Vector3(0, 0, (float)(_canvasShadow > 0 ? Math.Max(8, _canvasShadow) : 0));
    }

    private Brush MakeBackgroundBrush()
    {
        if (_bgStyle == ExportBackgroundStyle.Gradient)
        {
            return new LinearGradientBrush
            {
                StartPoint = new Point(0, 0),
                EndPoint = new Point(1, 1),
                GradientStops =
                {
                    new GradientStop { Color = _bgColor, Offset = 0 },
                    new GradientStop { Color = _bgColor2, Offset = 1 },
                },
            };
        }

        return new SolidColorBrush(_bgColor);
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

    private void OnImageHostSizeChanged(object sender, SizeChangedEventArgs e)
    {
        LayoutCanvas();
        RedrawOverlay();
    }

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
                var w = b.Width * scale;
                var h = b.Height * scale;

                // Committed redactions show a real blurred crop; the in-progress drag shows a
                // lightweight frosted rectangle (recomputing the blur every move is too costly).
                if (ann != _activeAnnotation)
                {
                    EnsureRedactPreview(ann);
                }

                if (ann.RedactPreview is not null)
                {
                    var img = new Image
                    {
                        Source = ann.RedactPreview,
                        Width = w,
                        Height = h,
                        Stretch = Stretch.Fill,
                    };
                    Canvas.SetLeft(img, tl.X);
                    Canvas.SetTop(img, tl.Y);
                    OverlayCanvas.Children.Add(img);
                }
                else
                {
                    var rect = new Rectangle
                    {
                        Width = w,
                        Height = h,
                        Fill = new SolidColorBrush(Color.FromArgb(200, 40, 40, 40)),
                        RadiusX = 4,
                        RadiusY = 4,
                    };
                    Canvas.SetLeft(rect, tl.X);
                    Canvas.SetTop(rect, tl.Y);
                    OverlayCanvas.Children.Add(rect);
                }
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
            // The export background is applied at save time, not during crop.
            var flattened = await RenderToBitmapAsync(includeBackground: false);
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
    private async Task<SoftwareBitmap> RenderToBitmapAsync(bool includeBackground = true)
    {
        if (_bitmap is null)
        {
            throw new InvalidOperationException("No bitmap loaded.");
        }

        await Task.CompletedTask;
        var device = CanvasDevice.GetSharedDevice();
        using var source = CanvasBitmap.CreateFromSoftwareBitmap(device, _bitmap);
        var imgW = (float)_bitmap.PixelWidth;
        var imgH = (float)_bitmap.PixelHeight;

        var hasBackground = _bgStyle != ExportBackgroundStyle.Transparent
            || _canvasPadding > 0
            || _canvasCornerRadius > 0
            || _canvasShadow > 0;

        // Simple path: no background/padding/corners/shadow, or caller opted out (crop pre-bake).
        if (!includeBackground || !hasBackground)
        {
            using var flatTarget = new CanvasRenderTarget(device, imgW, imgH, 96);
            using (var ds = flatTarget.CreateDrawingSession())
            {
                ds.Clear(Colors.Transparent);
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
                flatTarget.GetPixelBytes().AsBuffer(),
                BitmapPixelFormat.Bgra8,
                (int)imgW,
                (int)imgH,
                BitmapAlphaMode.Premultiplied);
        }

        // Composited path: padded background frame, rounded screenshot card, optional shadow.
        var pad = (float)Math.Round(_canvasPadding);
        var corner = (float)_canvasCornerRadius;
        var outW = imgW + pad * 2;
        var outH = imgH + pad * 2;

        using var target = new CanvasRenderTarget(device, outW, outH, 96);
        using (var ds = target.CreateDrawingSession())
        {
            ds.Clear(Colors.Transparent);

            var fullRect = new Rect(0, 0, outW, outH);
            if (_bgStyle == ExportBackgroundStyle.Solid)
            {
                ds.FillRectangle(fullRect, _bgColor);
            }
            else if (_bgStyle == ExportBackgroundStyle.Gradient)
            {
                using var brush = new CanvasLinearGradientBrush(device, _bgColor, _bgColor2)
                {
                    StartPoint = new Vector2(0, 0),
                    EndPoint = new Vector2(outW, outH),
                };
                ds.FillRectangle(fullRect, brush);
            }

            using var cardGeo = CanvasGeometry.CreateRoundedRectangle(device, pad, pad, imgW, imgH, corner, corner);

            if (_canvasShadow > 0)
            {
                using var shadowList = new CanvasCommandList(device);
                using (var sds = shadowList.CreateDrawingSession())
                {
                    sds.FillGeometry(cardGeo, Colors.Black);
                }

                using var shadow = new ShadowEffect
                {
                    Source = shadowList,
                    BlurAmount = (float)_canvasShadow,
                    ShadowColor = Color.FromArgb(120, 0, 0, 0),
                };
                ds.DrawImage(shadow, new Vector2(0, (float)(_canvasShadow * 0.35)));
            }

            using (ds.CreateLayer(1f, cardGeo))
            {
                ds.Transform = Matrix3x2.CreateTranslation(pad, pad);
                ds.DrawImage(source);
                foreach (var ann in _annotations.Where(a => a.Tool == EditTool.Redact))
                {
                    DrawRedaction(ds, source, ann);
                }
                foreach (var ann in _annotations.Where(a => a.Tool != EditTool.Redact))
                {
                    DrawAnnotationToSession(ds, ann);
                }
                ds.Transform = Matrix3x2.Identity;
            }
        }

        return SoftwareBitmap.CreateCopyFromBuffer(
            target.GetPixelBytes().AsBuffer(),
            BitmapPixelFormat.Bgra8,
            (int)outW,
            (int)outH,
            BitmapAlphaMode.Premultiplied);
    }

    private static float BlurAmountFor(RedactionLevel level) => level switch
    {
        RedactionLevel.Light => 6f,
        RedactionLevel.Medium => 12f,
        RedactionLevel.Heavy => 22f,
        _ => 12f,
    };

    private void EnsureRedactPreview(Annotation ann)
    {
        if (_canvasSource is null)
        {
            return;
        }

        var b = NormalizedBounds(ann);
        if (b.Width < 1 || b.Height < 1)
        {
            ann.RedactPreview = null;
            return;
        }

        // Reuse the cached preview when nothing relevant changed.
        if (ann.RedactPreview is not null
            && ann.RedactPreviewLevel == ann.Redaction
            && SameRect(ann.RedactPreviewBounds, b))
        {
            return;
        }

        try
        {
            var device = CanvasDevice.GetSharedDevice();
            var w = (int)Math.Round(b.Width);
            var h = (int)Math.Round(b.Height);
            if (w < 1 || h < 1)
            {
                return;
            }

            var srcRect = new Rect(b.X, b.Y, w, h);
            using var rt = new CanvasRenderTarget(device, w, h, 96);
            using (var ds = rt.CreateDrawingSession())
            {
                ds.Clear(Colors.Transparent);
                using var effect = BuildRedactEffect(_canvasSource, srcRect, ann.Redaction);
                ds.DrawImage(effect, new Rect(0, 0, w, h), srcRect);
            }

            var sb = SoftwareBitmap.CreateCopyFromBuffer(
                rt.GetPixelBytes().AsBuffer(),
                BitmapPixelFormat.Bgra8,
                w,
                h,
                BitmapAlphaMode.Premultiplied);

            var preview = new SoftwareBitmapSource();
            ann.RedactPreview = preview;
            ann.RedactPreviewBounds = b;
            ann.RedactPreviewLevel = ann.Redaction;
            _ = preview.SetBitmapAsync(sb).AsTask().ContinueWith(
                _ => DispatcherQueue.TryEnqueue(RedrawOverlayDefault),
                System.Threading.Tasks.TaskScheduler.Default);
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"Redact preview failed: {ex}");
        }
    }

    private void RedrawOverlayDefault() => RedrawOverlay();

    private static bool SameRect(Rect a, Rect b) =>
        Math.Abs(a.X - b.X) < 0.5 && Math.Abs(a.Y - b.Y) < 0.5
        && Math.Abs(a.Width - b.Width) < 0.5 && Math.Abs(a.Height - b.Height) < 0.5;

    private static ICanvasImage BuildRedactEffect(CanvasBitmap source, Rect region, RedactionLevel level)
    {
        var crop = new CropEffect { Source = source, SourceRectangle = region };
        // Clamp the edges so the blur doesn't pull transparency in from outside the crop.
        var border = new BorderEffect
        {
            Source = crop,
            ExtendX = CanvasEdgeBehavior.Clamp,
            ExtendY = CanvasEdgeBehavior.Clamp,
        };
        return new GaussianBlurEffect
        {
            Source = border,
            BlurAmount = BlurAmountFor(level),
            BorderMode = EffectBorderMode.Hard,
        };
    }

    private static void DrawRedaction(CanvasDrawingSession ds, CanvasBitmap source, Annotation ann)
    {
        var b = NormalizedBounds(ann);
        if (b.Width < 1 || b.Height < 1)
        {
            return;
        }

        var rect = new Rect(b.X, b.Y, b.Width, b.Height);
        using var effect = BuildRedactEffect(source, rect, ann.Redaction);
        ds.DrawImage(effect, rect, rect);
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
