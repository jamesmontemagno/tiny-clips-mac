using System.Runtime.InteropServices;
using Microsoft.UI.Dispatching;

namespace TinyClips.App;

/// <summary>
/// Registers system-wide hotkeys via Win32 <c>RegisterHotKey</c>. Because a tray-only
/// app has no long-lived foreground window, this owns a dedicated background thread that
/// creates a message-only window, registers the hotkeys against it and pumps a message
/// loop. <c>WM_HOTKEY</c> notifications are marshalled back to the UI dispatcher.
/// </summary>
internal sealed partial class GlobalHotKeyManager : IDisposable
{
    private const int WM_HOTKEY = 0x0312;
    private const int WM_CLOSE = 0x0010;
    private const uint MOD_NOREPEAT = 0x4000;
    private static readonly nint HWND_MESSAGE = new(-3);

    private readonly DispatcherQueue _dispatcher;
    private readonly Dictionary<int, Action> _callbacks = new();
    private readonly List<(int Modifiers, uint VirtualKey)> _pending = new();
    private readonly ManualResetEventSlim _ready = new(false);

    private Thread? _thread;
    private nint _hwnd;
    private WndProcDelegate? _wndProc; // held to keep the native callback alive
    private int _nextId = 1;
    private bool _disposed;

    private delegate nint WndProcDelegate(nint hWnd, uint msg, nint wParam, nint lParam);

    public GlobalHotKeyManager(DispatcherQueue dispatcher)
    {
        _dispatcher = dispatcher;
    }

    /// <summary>Queues a hotkey to register when <see cref="Start"/> is called.</summary>
    public void Add(int modifiers, uint virtualKey, Action callback)
    {
        if (virtualKey == 0)
        {
            return;
        }

        var id = _nextId++;
        _callbacks[id] = callback;
        _pending.Add((modifiers, virtualKey));
    }

    public void Start()
    {
        if (_thread is not null || _pending.Count == 0)
        {
            return;
        }

        _thread = new Thread(MessageLoop)
        {
            IsBackground = true,
            Name = "TinyClips.GlobalHotKeys",
        };
        _thread.SetApartmentState(ApartmentState.STA);
        _thread.Start();
        _ready.Wait(TimeSpan.FromSeconds(5));
    }

    private void MessageLoop()
    {
        var className = "TinyClipsHotKeyWindow_" + Guid.NewGuid().ToString("N");
        var hInstance = GetModuleHandleW(null);
        _wndProc = WndProc;

        var wndClass = new WNDCLASSW
        {
            lpfnWndProc = Marshal.GetFunctionPointerForDelegate(_wndProc),
            hInstance = hInstance,
            lpszClassName = className,
        };

        if (RegisterClassW(ref wndClass) == 0)
        {
            _ready.Set();
            return;
        }

        _hwnd = CreateWindowExW(0, className, string.Empty, 0, 0, 0, 0, 0, HWND_MESSAGE, 0, hInstance, 0);
        if (_hwnd == 0)
        {
            _ready.Set();
            return;
        }

        var index = 0;
        foreach (var (modifiers, virtualKey) in _pending)
        {
            var id = index + 1;
            RegisterHotKey(_hwnd, id, (uint)modifiers | MOD_NOREPEAT, virtualKey);
            index++;
        }

        _ready.Set();

        while (GetMessageW(out var msg, 0, 0, 0) > 0)
        {
            if (msg.message == WM_HOTKEY)
            {
                var id = (int)msg.wParam;
                if (_callbacks.TryGetValue(id, out var callback))
                {
                    _dispatcher.TryEnqueue(() => callback());
                }
            }

            TranslateMessage(ref msg);
            DispatchMessageW(ref msg);
        }

        for (var i = 0; i < _pending.Count; i++)
        {
            UnregisterHotKey(_hwnd, i + 1);
        }

        DestroyWindow(_hwnd);
        _hwnd = 0;
    }

    private nint WndProc(nint hWnd, uint msg, nint wParam, nint lParam)
        => DefWindowProcW(hWnd, msg, wParam, lParam);

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;

        if (_hwnd != 0)
        {
            PostMessageW(_hwnd, WM_CLOSE, 0, 0);
        }

        _thread?.Join(TimeSpan.FromSeconds(2));
        _ready.Dispose();
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct WNDCLASSW
    {
        public uint style;
        public nint lpfnWndProc;
        public int cbClsExtra;
        public int cbWndExtra;
        public nint hInstance;
        public nint hIcon;
        public nint hCursor;
        public nint hbrBackground;
        [MarshalAs(UnmanagedType.LPWStr)] public string? lpszMenuName;
        [MarshalAs(UnmanagedType.LPWStr)] public string lpszClassName;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MSG
    {
        public nint hwnd;
        public uint message;
        public nint wParam;
        public nint lParam;
        public uint time;
        public int ptX;
        public int ptY;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(nint hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterHotKey(nint hWnd, int id);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern ushort RegisterClassW(ref WNDCLASSW lpWndClass);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern nint CreateWindowExW(
        uint dwExStyle, string lpClassName, string lpWindowName, uint dwStyle,
        int x, int y, int nWidth, int nHeight,
        nint hWndParent, nint hMenu, nint hInstance, nint lpParam);

    [DllImport("user32.dll")]
    private static extern bool DestroyWindow(nint hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern nint DefWindowProcW(nint hWnd, uint msg, nint wParam, nint lParam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetMessageW(out MSG lpMsg, nint hWnd, uint wMsgFilterMin, uint wMsgFilterMax);

    [DllImport("user32.dll")]
    private static extern bool TranslateMessage(ref MSG lpMsg);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern nint DispatchMessageW(ref MSG lpMsg);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern bool PostMessageW(nint hWnd, uint msg, nint wParam, nint lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern nint GetModuleHandleW(string? lpModuleName);
}
