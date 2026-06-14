using Windows.Storage;
using TinyClips.Core.Models;

namespace TinyClips.Core.Services;

public sealed class SettingsService : ISettingsService
{
    private readonly Dictionary<string, object> _fallbackValues = new(StringComparer.OrdinalIgnoreCase);

    public AppTheme Theme
    {
        get => Get("Theme", AppTheme.Default);
        set => Set("Theme", value);
    }

    public string SaveDirectory
    {
        get => Get("SaveDirectory", string.Empty);
        set => Set("SaveDirectory", value);
    }

    public T Get<T>(string key, T defaultValue)
    {
        try
        {
            if (ApplicationData.Current.LocalSettings.Values.TryGetValue(key, out var storedValue))
            {
                if (storedValue is T typedValue)
                {
                    return typedValue;
                }

                if (storedValue is string stringValue && typeof(T).IsEnum)
                {
                    return (T)Enum.Parse(typeof(T), stringValue, true);
                }
            }
        }
        catch
        {
        }

        if (_fallbackValues.TryGetValue(key, out var fallbackValue))
        {
            if (fallbackValue is T typedValue)
            {
                return typedValue;
            }

            if (fallbackValue is string fallbackString && typeof(T).IsEnum)
            {
                return (T)Enum.Parse(typeof(T), fallbackString, true);
            }
        }

        return defaultValue;
    }

    public void Set<T>(string key, T value)
    {
        object persistedValue = value is null ? string.Empty : value;

        if (value is Enum enumValue)
        {
            persistedValue = enumValue.ToString();
        }

        try
        {
            ApplicationData.Current.LocalSettings.Values[key] = persistedValue;
        }
        catch
        {
            _fallbackValues[key] = persistedValue;
        }
    }
}
