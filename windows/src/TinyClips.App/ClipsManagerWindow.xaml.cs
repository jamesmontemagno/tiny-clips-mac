using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Linq;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using TinyClips.Core.Models;
using TinyClips.Core.Services;
using Windows.ApplicationModel.DataTransfer;
using Windows.Graphics;
using Windows.Storage;
using Windows.Storage.Streams;
using Windows.System;

namespace TinyClips.App;

/// <summary>
/// Library window listing every saved capture as a grid of cards with open / reveal /
/// copy / favorite / delete actions. Favoriting is a Pro feature; the action prompts an
/// upsell when Pro is locked.
/// </summary>
public sealed partial class ClipsManagerWindow : Window
{
    private readonly IClipsLibraryService _library;
    private readonly IEntitlementService _entitlement;
    private readonly ICaptureSettings _settings;
    private readonly ObservableCollection<ClipTile> _clips = new();
    private IReadOnlyList<ClipItem> _allClips = Array.Empty<ClipItem>();

    public ClipsManagerWindow()
    {
        _library = App.Services.GetRequiredService<IClipsLibraryService>();
        _entitlement = App.Services.GetRequiredService<IEntitlementService>();
        _settings = App.Services.GetRequiredService<ICaptureSettings>();

        InitializeComponent();

        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);
        AppWindow.Resize(new SizeInt32(960, 720));

        ApplyTheme();
        ClipsGrid.ItemsSource = _clips;
        Reload();
    }

    private void ApplyTheme()
    {
        RootGrid.RequestedTheme = _settings.Theme switch
        {
            AppTheme.Light => ElementTheme.Light,
            AppTheme.Dark => ElementTheme.Dark,
            _ => ElementTheme.Default,
        };
    }

    private void Reload()
    {
        _allClips = _library.GetClips();
        ApplyFilter();
    }

    private void ApplyFilter()
    {
        IEnumerable<ClipItem> filtered = FilterComboBox.SelectedIndex switch
        {
            1 => _allClips.Where(c => c.IsFavorite),
            2 => _allClips.Where(c => c.Type == CaptureType.Screenshot),
            3 => _allClips.Where(c => c.Type == CaptureType.Video),
            4 => _allClips.Where(c => c.Type == CaptureType.Gif),
            _ => _allClips,
        };

        _clips.Clear();
        foreach (var clip in filtered)
        {
            _clips.Add(new ClipTile(clip));
        }

        var hasClips = _clips.Count > 0;
        ClipsGrid.Visibility = hasClips ? Visibility.Visible : Visibility.Collapsed;
        EmptyState.Visibility = hasClips ? Visibility.Collapsed : Visibility.Visible;
    }

    private void OnRefreshClicked(object sender, RoutedEventArgs e) => Reload();

    private void OnFilterChanged(object sender, SelectionChangedEventArgs e) => ApplyFilter();

    private async void OnClipClicked(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is ClipTile clip)
        {
            await OpenAsync(clip.FilePath);
        }
    }

    private async void OnOpenClip(object sender, RoutedEventArgs e)
    {
        if (TagPath(sender) is { } path)
        {
            await OpenAsync(path);
        }
    }

    private void OnRevealClip(object sender, RoutedEventArgs e)
    {
        if (TagPath(sender) is { } path)
        {
            try
            {
                Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{path}\"") { UseShellExecute = true });
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Reveal failed: {ex}");
            }
        }
    }

    private async void OnCopyClip(object sender, RoutedEventArgs e)
    {
        if (TagPath(sender) is not { } path)
        {
            return;
        }

        try
        {
            var file = await StorageFile.GetFileFromPathAsync(path);
            var package = new DataPackage { RequestedOperation = DataPackageOperation.Copy };
            package.SetStorageItems(new[] { file });

            if (file.ContentType.StartsWith("image", StringComparison.OrdinalIgnoreCase))
            {
                package.SetBitmap(RandomAccessStreamReference.CreateFromFile(file));
            }

            Clipboard.SetContent(package);
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Copy failed: {ex}");
        }
    }

    private async void OnToggleFavorite(object sender, RoutedEventArgs e)
    {
        if (TagPath(sender) is not { } path)
        {
            return;
        }

        if (!_entitlement.IsProUnlocked)
        {
            await ShowProUpsellAsync();
            return;
        }

        _library.SetFavorite(path, !_library.IsFavorite(path));
        Reload();
    }

    private async void OnDeleteClip(object sender, RoutedEventArgs e)
    {
        if (TagPath(sender) is not { } path)
        {
            return;
        }

        var dialog = new ContentDialog
        {
            Title = "Delete clip?",
            Content = $"\"{System.IO.Path.GetFileName(path)}\" will be permanently deleted.",
            PrimaryButtonText = "Delete",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Close,
            XamlRoot = Content.XamlRoot,
        };

        if (await dialog.ShowAsync() == ContentDialogResult.Primary)
        {
            _library.Delete(path);
            Reload();
        }
    }

    private async void OnUploadClip(object sender, RoutedEventArgs e)
    {
        if (TagPath(sender) is null)
        {
            return;
        }

        // Upload/share is a Pro feature. The provider integration is intentionally not
        // wired in the direct build yet; gate it behind Pro with an informational prompt.
        if (!_entitlement.IsProUnlocked)
        {
            await ShowProUpsellAsync();
            return;
        }

        var dialog = new ContentDialog
        {
            Title = "Upload & share",
            Content = "Cloud upload and shareable links are coming soon to Tiny Clips Pro on Windows.",
            CloseButtonText = "OK",
            DefaultButton = ContentDialogButton.Close,
            XamlRoot = Content.XamlRoot,
        };

        await dialog.ShowAsync();
    }

    private async System.Threading.Tasks.Task ShowProUpsellAsync()
    {
        var dialog = new ContentDialog
        {
            Title = "Tiny Clips Pro",
            Content = "Organizing clips with favorites is a Pro feature. Pro will be available as a purchase in the Microsoft Store build.",
            CloseButtonText = "OK",
            DefaultButton = ContentDialogButton.Close,
            XamlRoot = Content.XamlRoot,
        };

        await dialog.ShowAsync();
    }

    private static async System.Threading.Tasks.Task OpenAsync(string path)
    {
        try
        {
            var file = await StorageFile.GetFileFromPathAsync(path);
            await Launcher.LaunchFileAsync(file);
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Open failed: {ex}");
        }
    }

    private static string? TagPath(object sender) =>
        (sender as FrameworkElement)?.Tag as string;
}
