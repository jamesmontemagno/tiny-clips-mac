using TinyClips.Core.Models;

namespace TinyClips.Core.Services;

public sealed class ClipStorageService : IClipStorageService
{
    private readonly ICaptureSettings _settings;
    private readonly IFileNameService _fileNames;
    private readonly IFileSystem _fileSystem;

    public ClipStorageService(ICaptureSettings settings, IFileNameService fileNames, IFileSystem fileSystem)
    {
        _settings = settings;
        _fileNames = fileNames;
        _fileSystem = fileSystem;
    }

    public string FileExtensionFor(CaptureType type) => _fileNames.FileExtensionFor(type);

    public string OutputDirectory(CaptureType type)
    {
        if (!string.IsNullOrWhiteSpace(_settings.SaveDirectory))
        {
            return _settings.SaveDirectory.Trim();
        }

        // Match the macOS app, which saves every capture type to a "TinyClips"
        // folder inside the user's Pictures library by default.
        var pictures = _fileSystem.GetFolderPath(Environment.SpecialFolder.MyPictures);
        return Path.Combine(pictures, "TinyClips");
    }

    public string GenerateFilePath(CaptureType type, string? fileExtension = null, string? stemSuffix = null)
    {
        var extension = string.IsNullOrWhiteSpace(fileExtension) ? FileExtensionFor(type) : fileExtension;
        var directory = OutputDirectory(type);

        _fileSystem.CreateDirectory(directory);

        var fileName = _fileNames.GeneratedFileName(type, extension);
        if (!string.IsNullOrWhiteSpace(stemSuffix))
        {
            var suffix = stemSuffix.Trim();
            var stem = Path.GetFileNameWithoutExtension(fileName);
            var extensionPart = Path.GetExtension(fileName);
            fileName = string.IsNullOrWhiteSpace(extensionPart) ? $"{stem} {suffix}" : $"{stem} {suffix}{extensionPart}";
        }

        var candidate = Path.Combine(directory, fileName);
        if (!_fileSystem.FileExists(candidate))
        {
            return candidate;
        }

        var baseStem = Path.GetFileNameWithoutExtension(candidate);
        var candidateExtension = Path.GetExtension(candidate);
        var index = 2;

        while (true)
        {
            var uniqueName = string.IsNullOrWhiteSpace(candidateExtension) ? $"{baseStem} {index}" : $"{baseStem} {index}{candidateExtension}";
            candidate = Path.Combine(directory, uniqueName);
            if (!_fileSystem.FileExists(candidate))
            {
                return candidate;
            }

            index++;
        }
    }
}
