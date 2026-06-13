using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media.Imaging;
using TinyClips.Core.Models;
using TinyClips.Core.Services;
using Windows.Foundation;
using Windows.Graphics.Imaging;
using Windows.Storage;
using Windows.Storage.Streams;

namespace TinyClips.App;

/// <summary>
/// Lightweight GIF trimmer: decodes every frame (with its delay), lets the user pick a
/// start/end frame range with two sliders, previews the boundary frames, then re-encodes the
/// kept frames to a new animated GIF. "Keep original" closes without trimming.
/// </summary>
public sealed partial class GifTrimmerWindow : Window
{
    private readonly string _filePath;
    private readonly List<SoftwareBitmap> _frames = new();
    private readonly List<ushort> _delays = new();
    private int _start;
    private int _end;
    private bool _ready;

    public GifTrimmerWindow(string filePath)
    {
        _filePath = filePath;

        InitializeComponent();

        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);
        AppWindow.Resize(new Windows.Graphics.SizeInt32(900, 760));

        var settings = App.Services.GetRequiredService<ICaptureSettings>();
        RootGrid.RequestedTheme = settings.Theme switch
        {
            AppTheme.Light => ElementTheme.Light,
            AppTheme.Dark => ElementTheme.Dark,
            _ => ElementTheme.Default,
        };

        Closed += OnWindowClosed;
        _ = LoadAsync();
    }

    private async Task LoadAsync()
    {
        try
        {
            var file = await StorageFile.GetFileFromPathAsync(_filePath);
            using var stream = await file.OpenAsync(FileAccessMode.Read);
            var decoder = await BitmapDecoder.CreateAsync(BitmapDecoder.GifDecoderId, stream);

            for (uint i = 0; i < decoder.FrameCount; i++)
            {
                var frame = await decoder.GetFrameAsync(i);
                var bitmap = await frame.GetSoftwareBitmapAsync(
                    BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied);
                _frames.Add(bitmap);
                _delays.Add(await ReadDelayAsync(frame));
            }

            if (_frames.Count == 0)
            {
                return;
            }

            _start = 0;
            _end = _frames.Count - 1;

            StartSlider.Maximum = _frames.Count - 1;
            EndSlider.Maximum = _frames.Count - 1;
            EndSlider.Value = _frames.Count - 1;

            _ready = true;
            UpdateLabels();
            await ShowFrameAsync(_start);
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"GIF trimmer load failed: {ex}");
        }
    }

    private static async Task<ushort> ReadDelayAsync(BitmapFrame frame)
    {
        try
        {
            var props = await frame.BitmapProperties.GetPropertiesAsync(new[] { "/grctlext/Delay" });
            if (props.TryGetValue("/grctlext/Delay", out var value) && value.Value is ushort delay)
            {
                return Math.Max((ushort)2, delay);
            }
        }
        catch
        {
            // Some frames may not carry the extension; fall back to a sensible default.
        }

        return 10;
    }

    // -- Range handling -------------------------------------------------------

    private void OnStartChanged(object sender, RangeBaseValueChangedEventArgs e)
    {
        if (!_ready)
        {
            return;
        }

        _start = (int)Math.Round(e.NewValue);
        if (_start > _end)
        {
            _start = _end;
            StartSlider.Value = _start;
        }

        UpdateLabels();
        _ = ShowFrameAsync(_start);
    }

    private void OnEndChanged(object sender, RangeBaseValueChangedEventArgs e)
    {
        if (!_ready)
        {
            return;
        }

        _end = (int)Math.Round(e.NewValue);
        if (_end < _start)
        {
            _end = _start;
            EndSlider.Value = _end;
        }

        UpdateLabels();
        _ = ShowFrameAsync(_end);
    }

    private async Task ShowFrameAsync(int index)
    {
        if (index < 0 || index >= _frames.Count)
        {
            return;
        }

        var source = new SoftwareBitmapSource();
        await source.SetBitmapAsync(_frames[index]);
        PreviewImage.Source = source;
    }

    private void UpdateLabels()
    {
        StartLabel.Text = (_start + 1).ToString();
        EndLabel.Text = (_end + 1).ToString();
        CountLabel.Text = $"{_end - _start + 1} of {_frames.Count} frames";
    }

    // -- Output ---------------------------------------------------------------

    private async void OnSaveTrimmed(object sender, RoutedEventArgs e)
    {
        if (!_ready)
        {
            return;
        }

        BusyBar.Visibility = Visibility.Visible;
        SaveTrimmedButton.IsEnabled = false;
        string? outputPath = null;

        try
        {
            var storage = App.Services.GetRequiredService<IClipStorageService>();
            outputPath = storage.GenerateFilePath(CaptureType.Gif, ".gif", " (trimmed)");
            var folder = await StorageFolder.GetFolderFromPathAsync(System.IO.Path.GetDirectoryName(outputPath)!);
            var outFile = await folder.CreateFileAsync(
                System.IO.Path.GetFileName(outputPath), CreationCollisionOption.GenerateUniqueName);

            using (var stream = await outFile.OpenAsync(FileAccessMode.ReadWrite))
            {
                var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.GifEncoderId, stream);

                var loopProps = new BitmapPropertySet
                {
                    { "/appext/application", new BitmapTypedValue(Encoding("NETSCAPE2.0"), PropertyType.UInt8Array) },
                    { "/appext/data", new BitmapTypedValue(new byte[] { 3, 1, 0, 0 }, PropertyType.UInt8Array) },
                };
                await encoder.BitmapProperties.SetPropertiesAsync(loopProps);

                for (var i = _start; i <= _end; i++)
                {
                    encoder.SetSoftwareBitmap(_frames[i]);

                    var delayProps = new BitmapPropertySet
                    {
                        { "/grctlext/Delay", new BitmapTypedValue(_delays[i], PropertyType.UInt16) },
                        { "/grctlext/Disposal", new BitmapTypedValue((byte)1, PropertyType.UInt8) },
                    };
                    await encoder.BitmapProperties.SetPropertiesAsync(delayProps);

                    if (i < _end)
                    {
                        await encoder.GoToNextFrameAsync();
                    }
                }

                await encoder.FlushAsync();
            }

            outputPath = outFile.Path;
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"GIF trim failed: {ex}");
            outputPath = null;
        }
        finally
        {
            BusyBar.Visibility = Visibility.Collapsed;
            SaveTrimmedButton.IsEnabled = true;
        }

        Completed?.Invoke(this, outputPath);
        Close();
    }

    private static byte[] Encoding(string ascii)
    {
        var bytes = new byte[ascii.Length];
        for (var i = 0; i < ascii.Length; i++)
        {
            bytes[i] = (byte)ascii[i];
        }

        return bytes;
    }

    private void OnDone(object sender, RoutedEventArgs e)
    {
        Completed?.Invoke(this, null);
        Close();
    }

    private void OnWindowClosed(object sender, WindowEventArgs e)
    {
        foreach (var frame in _frames)
        {
            frame.Dispose();
        }

        _frames.Clear();
    }

    /// <summary>Raised once when the window closes. Carries the trimmed file path, or null if untrimmed.</summary>
    public event EventHandler<string?>? Completed;
}
