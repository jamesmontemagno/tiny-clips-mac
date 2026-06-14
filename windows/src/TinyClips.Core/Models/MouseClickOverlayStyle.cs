namespace TinyClips.Core.Models;

public readonly record struct MouseClickOverlayStyle(
    string ColorHex,
    double Size,
    double StrokeWidth,
    double Opacity,
    double DurationSeconds);
