using TinyClips.Core.Models;

namespace TinyClips.Core.Services;

/// <summary>
/// File-system backed implementation of <see cref="IClipsLibraryService"/>. Scans the
/// configured Tiny Clips output directories for known capture extensions. Favorites are
/// persisted as a newline-separated list of paths in settings.
/// </summary>
public sealed class ClipsLibraryService : IClipsLibraryService
{
    private const string FavoritesKey = "favoriteClips";

    private static readonly IReadOnlyDictionary<string, CaptureType> ExtensionTypes =
        new Dictionary<string, CaptureType>(StringComparer.OrdinalIgnoreCase)
        {
            [".png"] = CaptureType.Screenshot,
            [".jpg"] = CaptureType.Screenshot,
            [".jpeg"] = CaptureType.Screenshot,
            [".gif"] = CaptureType.Gif,
            [".mp4"] = CaptureType.Video,
        };

    private readonly IClipStorageService _storage;
    private readonly ISettingsService _settings;
    private readonly IFileSystem _fileSystem;

    public ClipsLibraryService(IClipStorageService storage, ISettingsService settings, IFileSystem fileSystem)
    {
        _storage = storage;
        _settings = settings;
        _fileSystem = fileSystem;
    }

    public IReadOnlyList<ClipItem> GetClips()
    {
        var favorites = LoadFavorites();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var clips = new List<ClipItem>();

        foreach (var directory in OutputDirectories())
        {
            if (!Directory.Exists(directory))
            {
                continue;
            }

            foreach (var path in Directory.EnumerateFiles(directory))
            {
                if (!ExtensionTypes.TryGetValue(Path.GetExtension(path), out var type) || !seen.Add(path))
                {
                    continue;
                }

                var info = new FileInfo(path);
                clips.Add(new ClipItem
                {
                    FilePath = path,
                    FileName = info.Name,
                    Type = type,
                    CreatedAt = info.LastWriteTime,
                    SizeBytes = info.Length,
                    IsFavorite = favorites.Contains(path),
                });
            }
        }

        return clips
            .OrderByDescending(c => c.IsFavorite)
            .ThenByDescending(c => c.CreatedAt)
            .ToList();
    }

    public bool IsFavorite(string filePath) => LoadFavorites().Contains(filePath);

    public void SetFavorite(string filePath, bool isFavorite)
    {
        var favorites = LoadFavorites();
        if (isFavorite)
        {
            favorites.Add(filePath);
        }
        else
        {
            favorites.Remove(filePath);
        }

        _settings.Set(FavoritesKey, string.Join('\n', favorites));
    }

    public bool Delete(string filePath)
    {
        if (!_fileSystem.FileExists(filePath))
        {
            return false;
        }

        File.Delete(filePath);
        SetFavorite(filePath, false);
        return true;
    }

    private IEnumerable<string> OutputDirectories()
    {
        // Distinct because all three may resolve to the same custom save directory.
        return new[]
            {
                _storage.OutputDirectory(CaptureType.Screenshot),
                _storage.OutputDirectory(CaptureType.Video),
                _storage.OutputDirectory(CaptureType.Gif),
            }
            .Distinct(StringComparer.OrdinalIgnoreCase);
    }

    private HashSet<string> LoadFavorites()
    {
        var raw = _settings.Get(FavoritesKey, string.Empty);
        var set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        if (string.IsNullOrEmpty(raw))
        {
            return set;
        }

        foreach (var line in raw.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            set.Add(line);
        }

        return set;
    }
}
