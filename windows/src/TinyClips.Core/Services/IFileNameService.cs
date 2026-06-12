using TinyClips.Core.Models;

namespace TinyClips.Core.Services;

public interface IFileNameService
{
    string GeneratedFileName(CaptureType type, string fileExtension, DateTime? date = null);
    string NamingPreview(CaptureType type);
    string FileExtensionFor(CaptureType type);
}
