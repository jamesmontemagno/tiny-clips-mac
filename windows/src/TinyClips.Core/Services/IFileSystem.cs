namespace TinyClips.Core.Services;

public interface IFileSystem
{
    bool FileExists(string path);
    void CreateDirectory(string path);
    string GetFolderPath(Environment.SpecialFolder folder);
}
