using System;
using System.Threading.Tasks;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media.Imaging;
using TinyClips.Core.Models;
using TinyClips.Core.Services;
using Windows.Foundation;
using Windows.Graphics.Imaging;
using Windows.Storage;
using Windows.Storage.Pickers;
using Windows.Storage.Streams;
using Windows.ApplicationModel.DataTransfer;

namespace TinyClips.App;

/// <summary>
/// Lightweight screenshot editor: shows a captured image, lets the user drag a crop
/// rectangle and apply it, then save (overwrite), save a copy, or copy to the clipboard.
/// All edits operate on an in-memory <see cref="SoftwareBitmap"/>; the original file is only
/// touched when the user saves.
/// </summary>
public sealed partial class ScreenshotEditorWindow : Window
{
    private readonly string _filePath;
    private SoftwareBitmap? _bitmap;
    private bool _dragging;
    private Point _dragStart;

    public ScreenshotEditorWindow(string filePath)
    {
        _filePath = filePath;

        InitializeComponent();

        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);
        AppWindow.Resize(new Windows.Graphics.SizeInt32(1000, 760));

        var settings = App.Services.GetRequiredService<ICaptureSettings>();
        RootGrid.RequestedTheme = settings.Theme switch
        {
            AppTheme.Light => ElementTheme.Light,
            AppTheme.Dark => ElementTheme.Dark,
            _ => ElementTheme.Default,
        };

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

    // -- Crop selection -------------------------------------------------------

    private void OnPointerPressed(object sender, PointerRoutedEventArgs e)
    {
        _dragging = true;
        _dragStart = e.GetCurrentPoint(OverlayCanvas).Position;
        Canvas.SetLeft(SelectionRect, _dragStart.X);
        Canvas.SetTop(SelectionRect, _dragStart.Y);
        SelectionRect.Width = 0;
        SelectionRect.Height = 0;
        SelectionRect.Visibility = Visibility.Visible;
        OverlayCanvas.CapturePointer(e.Pointer);
    }

    private void OnPointerMoved(object sender, PointerRoutedEventArgs e)
    {
        if (!_dragging)
        {
            return;
        }

        var p = e.GetCurrentPoint(OverlayCanvas).Position;
        var x = Math.Min(p.X, _dragStart.X);
        var y = Math.Min(p.Y, _dragStart.Y);
        Canvas.SetLeft(SelectionRect, x);
        Canvas.SetTop(SelectionRect, y);
        SelectionRect.Width = Math.Abs(p.X - _dragStart.X);
        SelectionRect.Height = Math.Abs(p.Y - _dragStart.Y);
    }

    private void OnPointerReleased(object sender, PointerRoutedEventArgs e)
    {
        _dragging = false;
        OverlayCanvas.ReleasePointerCapture(e.Pointer);
        ApplyCropButton.IsEnabled = SelectionRect.Width > 4 && SelectionRect.Height > 4;
    }

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
            var cropped = await CropAsync(_bitmap, rect);
            await SetBitmapAsync(cropped);
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"Crop failed: {ex}");
        }
    }

    /// <summary>
    /// Converts the DIP selection rectangle (in overlay-canvas coordinates) to integer pixel
    /// bounds on the source bitmap, accounting for Uniform letterboxing of the displayed image.
    /// </summary>
    private BitmapBounds? MapSelectionToPixels()
    {
        if (_bitmap is null)
        {
            return null;
        }

        double imgW = _bitmap.PixelWidth;
        double imgH = _bitmap.PixelHeight;
        double hostW = ImageHost.ActualWidth;
        double hostH = ImageHost.ActualHeight;
        if (imgW <= 0 || imgH <= 0 || hostW <= 0 || hostH <= 0)
        {
            return null;
        }

        var scale = Math.Min(hostW / imgW, hostH / imgH);
        var displayedW = imgW * scale;
        var displayedH = imgH * scale;
        var offsetX = (hostW - displayedW) / 2.0;
        var offsetY = (hostH - displayedH) / 2.0;

        var selLeft = Canvas.GetLeft(SelectionRect);
        var selTop = Canvas.GetTop(SelectionRect);

        var pxLeft = (selLeft - offsetX) / scale;
        var pxTop = (selTop - offsetY) / scale;
        var pxRight = (selLeft + SelectionRect.Width - offsetX) / scale;
        var pxBottom = (selTop + SelectionRect.Height - offsetY) / scale;

        pxLeft = Math.Clamp(pxLeft, 0, imgW);
        pxTop = Math.Clamp(pxTop, 0, imgH);
        pxRight = Math.Clamp(pxRight, 0, imgW);
        pxBottom = Math.Clamp(pxBottom, 0, imgH);

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

    // -- Output ---------------------------------------------------------------

    private async void OnSave(object sender, RoutedEventArgs e)
    {
        if (_bitmap is null)
        {
            return;
        }

        await EncodeToFileAsync(_filePath);
        Close();
    }

    private async void OnSaveCopy(object sender, RoutedEventArgs e)
    {
        if (_bitmap is null)
        {
            return;
        }

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
            using var stream = new InMemoryRandomAccessStream();
            var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.PngEncoderId, stream);
            encoder.SetSoftwareBitmap(_bitmap);
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
            var isPng = path.EndsWith(".png", StringComparison.OrdinalIgnoreCase);
            var encoderId = isPng ? BitmapEncoder.PngEncoderId : BitmapEncoder.JpegEncoderId;

            var folder = await StorageFolder.GetFolderFromPathAsync(System.IO.Path.GetDirectoryName(path)!);
            var file = await folder.CreateFileAsync(System.IO.Path.GetFileName(path), CreationCollisionOption.ReplaceExisting);
            using var stream = await file.OpenAsync(FileAccessMode.ReadWrite);
            var encoder = await BitmapEncoder.CreateAsync(encoderId, stream);

            SoftwareBitmap toEncode = _bitmap;
            if (!isPng && _bitmap.BitmapAlphaMode != BitmapAlphaMode.Ignore)
            {
                toEncode = SoftwareBitmap.Convert(_bitmap, BitmapPixelFormat.Bgra8, BitmapAlphaMode.Ignore);
            }

            encoder.SetSoftwareBitmap(toEncode);
            await encoder.FlushAsync();

            if (!ReferenceEquals(toEncode, _bitmap))
            {
                toEncode.Dispose();
            }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"Save failed: {ex}");
        }
    }
}
