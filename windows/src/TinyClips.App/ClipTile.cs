using System;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using TinyClips.Core.Models;

namespace TinyClips.App;

/// <summary>
/// View model wrapper around a <see cref="ClipItem"/> that exposes UI-typed properties
/// (image source, visibilities) directly, so the Clips Manager grid can bind with
/// <c>x:Bind</c> without value converters — converters can't compile against a Window root.
/// </summary>
public sealed class ClipTile
{
    public ClipTile(ClipItem item)
    {
        Item = item;
        if (item.IsImagePreview)
        {
            try
            {
                Preview = new BitmapImage(new Uri(item.FilePath));
            }
            catch
            {
                Preview = null;
            }
        }
    }

    public ClipItem Item { get; }

    public string FilePath => Item.FilePath;

    public string FileName => Item.FileName;

    public string SizeDisplay => Item.SizeDisplay;

    public ImageSource? Preview { get; }

    public Visibility PreviewVisibility => Item.IsImagePreview ? Visibility.Visible : Visibility.Collapsed;

    public Visibility PlaceholderVisibility => Item.IsImagePreview ? Visibility.Collapsed : Visibility.Visible;

    public Visibility FavoriteVisibility => Item.IsFavorite ? Visibility.Visible : Visibility.Collapsed;

    public Visibility EditVisibility => Item.Type == CaptureType.Screenshot ? Visibility.Visible : Visibility.Collapsed;
}
