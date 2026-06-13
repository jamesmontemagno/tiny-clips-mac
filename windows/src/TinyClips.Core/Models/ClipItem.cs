namespace TinyClips.Core.Models;

/// <summary>
/// A single saved capture surfaced in the Clips Manager library. Backed by a file on
/// disk in one of the Tiny Clips output directories.
/// </summary>
public sealed class ClipItem
{
    public required string FilePath { get; init; }

    public required string FileName { get; init; }

    public required CaptureType Type { get; init; }

    public required DateTime CreatedAt { get; init; }

    public required long SizeBytes { get; init; }

    public bool IsFavorite { get; set; }

    /// <summary>Human-friendly size such as "1.2 MB" for display in the library.</summary>
    public string SizeDisplay => SizeBytes switch
    {
        >= 1024L * 1024L => $"{SizeBytes / (1024.0 * 1024.0):0.0} MB",
        >= 1024L => $"{SizeBytes / 1024.0:0} KB",
        _ => $"{SizeBytes} B",
    };

    /// <summary>True when the clip can be previewed directly as an image (screenshot or GIF).</summary>
    public bool IsImagePreview => Type is CaptureType.Screenshot or CaptureType.Gif;
}
