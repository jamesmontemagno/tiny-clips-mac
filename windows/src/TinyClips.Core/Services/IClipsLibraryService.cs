using TinyClips.Core.Models;

namespace TinyClips.Core.Services;

/// <summary>
/// Read/maintain the library of saved captures shown in the Clips Manager. Clips are
/// discovered by scanning the Tiny Clips output directories, so the library reflects the
/// real files on disk without a separate database to keep in sync.
/// </summary>
public interface IClipsLibraryService
{
    /// <summary>Enumerates all saved clips across the screenshot/video/GIF output folders, newest first.</summary>
    IReadOnlyList<ClipItem> GetClips();

    /// <summary>Returns whether the given clip path is marked as a favorite.</summary>
    bool IsFavorite(string filePath);

    /// <summary>Marks or unmarks a clip as a favorite (persisted across launches).</summary>
    void SetFavorite(string filePath, bool isFavorite);

    /// <summary>Deletes the clip file from disk. Returns true when the file was removed.</summary>
    bool Delete(string filePath);
}
