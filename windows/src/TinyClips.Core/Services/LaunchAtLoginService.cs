using System.Diagnostics;
using Microsoft.Win32;

namespace TinyClips.Core.Services;

public sealed class LaunchAtLoginService : ILaunchAtLoginService
{
    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string RunValueName = "TinyClips";

    public bool IsEnabled
    {
        get
        {
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, false);
                return string.Equals((string?)key?.GetValue(RunValueName), GetExecutablePath(), StringComparison.OrdinalIgnoreCase);
            }
            catch
            {
                return false;
            }
        }
        set => Apply(value);
    }

    public void Sync(bool enabled) => Apply(enabled);

    public void Apply(bool enabled)
    {
        try
        {
            var executablePath = GetExecutablePath();
            if (string.IsNullOrWhiteSpace(executablePath))
            {
                return;
            }

            using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, true) ?? Registry.CurrentUser.CreateSubKey(RunKeyPath);
            if (key is null)
            {
                return;
            }

            if (enabled)
            {
                key.SetValue(RunValueName, executablePath);
                return;
            }

            key.DeleteValue(RunValueName, false);
        }
        catch
        {
        }
    }

    private static string GetExecutablePath()
    {
        var processPath = Environment.ProcessPath;
        if (!string.IsNullOrWhiteSpace(processPath))
        {
            return processPath;
        }

        return Process.GetCurrentProcess().MainModule?.FileName ?? string.Empty;
    }
}
