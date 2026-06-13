using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using TinyClips.Core.Capture;
using Windows.Graphics;

namespace TinyClips.App;

/// <summary>
/// Borderless, always-on-top outline shown around a selected region during countdown.
/// </summary>
public sealed partial class RegionIndicatorWindow : Window
{
    private bool _closed;

    public RegionIndicatorWindow()
    {
        InitializeComponent();

        ConfigurePresenter();
        Closed += OnClosed;
    }

    public void Show(PixelRect regionInPhysicalPixels)
    {
        var rect = new RectInt32(
            regionInPhysicalPixels.X,
            regionInPhysicalPixels.Y,
            Math.Max(1, regionInPhysicalPixels.Width),
            Math.Max(1, regionInPhysicalPixels.Height));

        AppWindow.MoveAndResize(rect);
        AppWindow.Show(false);
    }

    public void ClosePanel()
    {
        if (_closed)
        {
            return;
        }

        _closed = true;
        Close();
    }

    private void ConfigurePresenter()
    {
        if (AppWindow.Presenter is OverlappedPresenter presenter)
        {
            presenter.SetBorderAndTitleBar(false, false);
            presenter.IsAlwaysOnTop = true;
            presenter.IsMaximizable = false;
            presenter.IsMinimizable = false;
            presenter.IsResizable = false;
        }

        AppWindow.IsShownInSwitchers = false;
    }

    private void OnClosed(object sender, WindowEventArgs args)
    {
        _closed = true;
    }
}
