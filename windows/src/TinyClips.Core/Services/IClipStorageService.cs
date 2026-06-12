using TinyClips.Core.Models;

namespace TinyClips.Core.Services;

public interface IClipStorageService
{
    string FileExtensionFor(CaptureType type);
    string GenerateFilePath(CaptureType type, string? fileExtension = null, string? stemSuffix = null);
    string OutputDirectory(CaptureType type);
}
