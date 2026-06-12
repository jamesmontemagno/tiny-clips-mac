using TinyClips.Core.Models;

namespace TinyClips.Core.Services;

public interface IHotKeyService
{
    HotKeyDefinition GetBinding(CaptureType type);
    void SetBinding(CaptureType type, HotKeyDefinition binding);
    HotKeyDefinition DefaultFor(CaptureType type);
}
