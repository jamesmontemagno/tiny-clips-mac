using System;
using System.ComponentModel;
using System.Globalization;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using TinyClips.Core.Services;
using Windows.Graphics;
using Windows.Storage;
using Windows.Storage.Pickers;
using Windows.UI;

namespace TinyClips.App;

public sealed partial class SettingsWindow : Window
{
    public SettingsViewModel ViewModel { get; }

    public SettingsWindow()
    {
        ViewModel = new SettingsViewModel(
            App.Services.GetRequiredService<ICaptureSettings>(),
            App.Services.GetRequiredService<IHotKeyService>(),
            App.Services.GetRequiredService<ILaunchAtLoginService>(),
            App.Services.GetRequiredService<IEntitlementService>());

        InitializeComponent();

        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);

        SettingsNavigation.SelectedItem = GeneralNavigationItem;
        ShowSettingsSection("General");

        AppWindow.Resize(new SizeInt32(1040, 820));

        ApplyTheme();
        UpdateMouseClickPreview();
        ViewModel.ThemeChanged += ApplyTheme;
        ViewModel.PropertyChanged += OnViewModelPropertyChanged;
        Closed += OnClosed;
    }

    private void OnClosed(object sender, WindowEventArgs args)
    {
        ViewModel.ThemeChanged -= ApplyTheme;
        ViewModel.PropertyChanged -= OnViewModelPropertyChanged;
        Closed -= OnClosed;
    }

    private void OnViewModelPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(SettingsViewModel.MouseClickPreviewColorHex) ||
            e.PropertyName == nameof(SettingsViewModel.VideoMouseClickColorHex))
        {
            UpdateMouseClickPreview();
        }
    }

    private void UpdateMouseClickPreview()
    {
        MouseClickPreviewRing.Stroke = new SolidColorBrush(ParseHexColor(ViewModel.MouseClickPreviewColorHex));
    }

    private static Color ParseHexColor(string? hex)
    {
        var s = (hex ?? string.Empty).Trim().TrimStart('#');
        if (s.Length == 8)
        {
            s = s[2..];
        }

        if (s.Length == 6 &&
            byte.TryParse(s.AsSpan(0, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var r) &&
            byte.TryParse(s.AsSpan(2, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var g) &&
            byte.TryParse(s.AsSpan(4, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var b))
        {
            return Color.FromArgb(255, r, g, b);
        }

        return Color.FromArgb(255, 255, 214, 10);
    }

    private void ApplyTheme()
    {
        RootGrid.RequestedTheme = ViewModel.ThemeIndex switch
        {
            1 => ElementTheme.Light,
            2 => ElementTheme.Dark,
            _ => ElementTheme.Default,
        };
    }

    private void OnSettingsNavigationSelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.SelectedItem is NavigationViewItem { Tag: string sectionTag })
        {
            ShowSettingsSection(sectionTag);
        }
    }

    private void ShowSettingsSection(string sectionTag)
    {
        GeneralSection.Visibility = sectionTag == "General" ? Visibility.Visible : Visibility.Collapsed;
        ScreenshotSection.Visibility = sectionTag == "Screenshot" ? Visibility.Visible : Visibility.Collapsed;
        VideoSection.Visibility = sectionTag == "Video" ? Visibility.Visible : Visibility.Collapsed;
        GifSection.Visibility = sectionTag == "Gif" ? Visibility.Visible : Visibility.Collapsed;
        MouseClicksSection.Visibility = sectionTag == "MouseClicks" ? Visibility.Visible : Visibility.Collapsed;
        BrandingSection.Visibility = sectionTag == "Branding" ? Visibility.Visible : Visibility.Collapsed;
        HotkeysSection.Visibility = sectionTag == "Hotkeys" ? Visibility.Visible : Visibility.Collapsed;
        ProSection.Visibility = sectionTag == "Pro" ? Visibility.Visible : Visibility.Collapsed;
    }

    private async void OnBrowseSaveDirectory(object sender, RoutedEventArgs e)
    {
        var picker = new FolderPicker
        {
            SuggestedStartLocation = PickerLocationId.PicturesLibrary,
        };
        picker.FileTypeFilter.Add("*");

        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        WinRT.Interop.InitializeWithWindow.Initialize(picker, hwnd);

        StorageFolder? folder = await picker.PickSingleFolderAsync();
        if (folder is not null)
        {
            ViewModel.SaveDirectory = folder.Path;
        }
    }
}
