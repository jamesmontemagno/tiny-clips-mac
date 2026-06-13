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
                var storedValue = ((string?)key?.GetValue(RunValueName))?.Trim('"');
                return string.Equals(storedValue, GetExecutablePath(), StringComparison.OrdinalIgnoreCase);
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
                // MSIX should use windows.startupTask + StartupTask; per-version install paths break registry launch after updates.
                key.SetValue(RunValueName, QuoteExecutablePath(executablePath));
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

    private static string QuoteExecutablePath(string executablePath) => $"\"{executablePath.Trim('"')}\"";
}
