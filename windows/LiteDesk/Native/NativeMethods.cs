using System.Runtime.InteropServices;

namespace LiteDesk.Native;

// Raw Win32 P/Invoke surface shared by Phase 3 (GDI screen capture) and
// Phase 4 (SendInput mouse injection). This project targets win-x64 only
// (see LiteDesk.csproj / the plan's `dotnet publish -r win-x64`), so struct
// layouts below are sized for x64 (8-byte IntPtr) rather than trying to stay
// portable to x86.
internal static class NativeMethods
{
    // ---------------------------------------------------------------
    // GDI: primary-monitor screen capture (Phase 3 / Services/ScreenCapture.cs)
    // ---------------------------------------------------------------

    [DllImport("user32.dll")]
    internal static extern IntPtr GetDC(IntPtr hWnd);

    [DllImport("user32.dll")]
    internal static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);

    [DllImport("gdi32.dll")]
    internal static extern IntPtr CreateCompatibleDC(IntPtr hdc);

    [DllImport("gdi32.dll")]
    internal static extern IntPtr CreateCompatibleBitmap(IntPtr hdc, int nWidth, int nHeight);

    [DllImport("gdi32.dll")]
    internal static extern IntPtr SelectObject(IntPtr hdc, IntPtr hgdiobj);

    [DllImport("gdi32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool BitBlt(
        IntPtr hdcDest, int xDest, int yDest, int width, int height,
        IntPtr hdcSrc, int xSrc, int ySrc, uint rop);

    [DllImport("gdi32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool DeleteDC(IntPtr hdc);

    [DllImport("gdi32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool DeleteObject(IntPtr hObject);

    [DllImport("user32.dll")]
    internal static extern int GetSystemMetrics(int nIndex);

    internal const uint SRCCOPY = 0x00CC0020;

    // GetSystemMetrics indices.
    internal const int SM_CXSCREEN = 0;
    internal const int SM_CYSCREEN = 1;
    internal const int SM_XVIRTUALSCREEN = 76;
    internal const int SM_YVIRTUALSCREEN = 77;
    internal const int SM_CXVIRTUALSCREEN = 78;
    internal const int SM_CYVIRTUALSCREEN = 79;

    // ---------------------------------------------------------------
    // user32: mouse input injection (Phase 4 / Services/MouseInjector.cs)
    // ---------------------------------------------------------------

    [StructLayout(LayoutKind.Sequential)]
    internal struct MOUSEINPUT
    {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    // Native INPUT is a tagged union (DWORD type + union { MOUSEINPUT;
    // KEYBDINPUT; HARDWAREINPUT; }). `mi` and `ki` are pinned at
    // FieldOffset(8) rather than relying on implicit Sequential-layout
    // padding: on x64 the union must start 8-byte-aligned (it contains an
    // IntPtr field), so the native compiler inserts 4 bytes of padding
    // after the 4-byte `type` field before the union begins — offset 8
    // reproduces that exactly. Total size is pinned to 40 bytes
    // (8 + sizeof(MOUSEINPUT), where MOUSEINPUT itself is 32 bytes on x64:
    // 5 x 4-byte fields + 4 bytes padding to 8-byte-align the trailing
    // IntPtr), matching native `sizeof(INPUT)` on x64. KEYBDINPUT is only
    // 24 bytes (2 x 2-byte + 2 x 4-byte fields + 4 bytes padding + IntPtr),
    // which fits comfortably inside that same 40-byte footprint at the
    // same offset 8.
    [StructLayout(LayoutKind.Explicit, Size = 40)]
    internal struct INPUT
    {
        [FieldOffset(0)]
        public int type;

        [FieldOffset(8)]
        public MOUSEINPUT mi;

        [FieldOffset(8)]
        public KEYBDINPUT ki;
    }

    internal const int INPUT_MOUSE = 0;
    internal const int INPUT_KEYBOARD = 1;

    internal const uint MOUSEEVENTF_MOVE = 0x0001;
    internal const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    internal const uint MOUSEEVENTF_LEFTUP = 0x0004;
    internal const uint MOUSEEVENTF_RIGHTDOWN = 0x0008;
    internal const uint MOUSEEVENTF_RIGHTUP = 0x0010;
    internal const uint MOUSEEVENTF_MIDDLEDOWN = 0x0020;
    internal const uint MOUSEEVENTF_MIDDLEUP = 0x0040;
    internal const uint MOUSEEVENTF_WHEEL = 0x0800;
    internal const uint MOUSEEVENTF_HWHEEL = 0x1000;
    internal const uint MOUSEEVENTF_VIRTUALDESK = 0x4000;
    internal const uint MOUSEEVENTF_ABSOLUTE = 0x8000;

    internal const int WHEEL_DELTA = 120;

    [DllImport("user32.dll", SetLastError = true)]
    internal static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    // ---------------------------------------------------------------
    // user32: keyboard input injection (Services/KeyInjector.cs)
    // ---------------------------------------------------------------

    [StructLayout(LayoutKind.Sequential)]
    internal struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    internal const uint KEYEVENTF_KEYUP = 0x0002;
}
