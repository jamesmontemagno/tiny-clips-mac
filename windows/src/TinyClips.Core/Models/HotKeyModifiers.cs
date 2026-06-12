namespace TinyClips.Core.Models;

[Flags]
public enum HotKeyModifiers
{
    None = 0,
    Alt = 1,
    Control = 2,
    Shift = 4,
    Win = 8,
}
