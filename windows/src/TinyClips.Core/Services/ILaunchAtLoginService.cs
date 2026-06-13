namespace TinyClips.Core.Services;

public interface ILaunchAtLoginService
{
    bool IsEnabled { get; set; }

    void Sync(bool enabled);
    void Apply(bool enabled);
}
