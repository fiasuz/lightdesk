using System.Windows;
using System.Windows.Media.Imaging;
using LiteDesk.Native;

namespace LiteDesk.Services;

// Primary-monitor screen capture via GDI BitBlt, encoded as JPEG through
// WPF's WIC-backed JpegBitmapEncoder. Runs on a System.Threading.Timer at
// ~8fps (125ms) — HostServer starts/stops this on ViewerConnected /
// ViewerDisconnected so no capture happens (no CPU/GDI cost) while nobody
// is watching, which the Electron app does not do (it captures continuously
// whenever host mode is "started").
public sealed class ScreenCapture
{
    private const int FrameIntervalMs = 125; // 1000/8 ≈ 8fps, matching the current app
    private const int JpegQuality = 50; // matches canvas.toBlob('image/jpeg', 0.5)

    private readonly object _stateLock = new();
    private System.Threading.Timer? _timer;
    private bool _captureInFlight;

    public event Action<byte[]>? FrameCaptured;
    public event Action<string>? CaptureError;

    // The primary monitor's pixel size, computed once at Start() from the
    // same GetSystemMetrics values used for every capture region — this is
    // the single source of truth HostServer uses both for the auth-ok
    // width/height and for MouseInjector's coordinate scaling, so they can
    // never drift apart.
    public static (int Width, int Height) GetPrimaryMonitorSize()
    {
        int width = NativeMethods.GetSystemMetrics(NativeMethods.SM_CXSCREEN);
        int height = NativeMethods.GetSystemMetrics(NativeMethods.SM_CYSCREEN);
        return (width, height);
    }

    public void Start()
    {
        lock (_stateLock)
        {
            if (_timer is not null) return;

            (int width, int height) = GetPrimaryMonitorSize();
            _timer = new System.Threading.Timer(_ => CaptureTick(width, height), null, 0, FrameIntervalMs);
        }
    }

    public void Stop()
    {
        lock (_stateLock)
        {
            _timer?.Dispose();
            _timer = null;
        }
    }

    private void CaptureTick(int width, int height)
    {
        // Timer callbacks can overlap if a capture+encode takes longer than
        // the 125ms period; skip this tick rather than letting captures
        // pile up on the thread pool.
        lock (_stateLock)
        {
            if (_captureInFlight) return;
            _captureInFlight = true;
        }

        try
        {
            byte[]? jpeg = CaptureFrameAsJpeg(width, height);
            if (jpeg is not null) FrameCaptured?.Invoke(jpeg);
        }
        catch (Exception ex)
        {
            CaptureError?.Invoke(ex.Message);
        }
        finally
        {
            lock (_stateLock) { _captureInFlight = false; }
        }
    }

    private static byte[]? CaptureFrameAsJpeg(int width, int height)
    {
        if (width <= 0 || height <= 0) return null;

        IntPtr screenDC = IntPtr.Zero;
        IntPtr memDC = IntPtr.Zero;
        IntPtr bitmap = IntPtr.Zero;
        IntPtr oldBitmap = IntPtr.Zero;

        try
        {
            screenDC = NativeMethods.GetDC(IntPtr.Zero);
            if (screenDC == IntPtr.Zero) return null;

            memDC = NativeMethods.CreateCompatibleDC(screenDC);
            if (memDC == IntPtr.Zero) return null;

            bitmap = NativeMethods.CreateCompatibleBitmap(screenDC, width, height);
            if (bitmap == IntPtr.Zero) return null;

            oldBitmap = NativeMethods.SelectObject(memDC, bitmap);

            bool ok = NativeMethods.BitBlt(memDC, 0, 0, width, height, screenDC, 0, 0, NativeMethods.SRCCOPY);
            if (!ok) return null;

            // CreateBitmapSourceFromHBitmap copies the pixel data into a
            // new managed bitmap surface synchronously — the returned
            // BitmapSource does not keep a live dependency on `bitmap`, so
            // it's safe to delete the HBITMAP afterward (in `finally`,
            // below) once this call returns.
            BitmapSource bitmapSource = System.Windows.Interop.Imaging.CreateBitmapSourceFromHBitmap(
                bitmap, IntPtr.Zero, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
            bitmapSource.Freeze();

            var encoder = new JpegBitmapEncoder { QualityLevel = JpegQuality };
            encoder.Frames.Add(BitmapFrame.Create(bitmapSource));

            using var ms = new MemoryStream();
            encoder.Save(ms);
            return ms.ToArray();
        }
        finally
        {
            // Careful, ordered cleanup — this runs 8x/sec, so any leak here
            // exhausts the process's GDI handle quota (default 10,000/process)
            // within minutes: deselect `bitmap` from memDC before deleting
            // it, then delete the memory DC, then release the screen DC
            // (GetDC/ReleaseDC must be paired, unlike Create*/Delete*).
            if (memDC != IntPtr.Zero && oldBitmap != IntPtr.Zero)
            {
                NativeMethods.SelectObject(memDC, oldBitmap);
            }
            if (bitmap != IntPtr.Zero) NativeMethods.DeleteObject(bitmap);
            if (memDC != IntPtr.Zero) NativeMethods.DeleteDC(memDC);
            if (screenDC != IntPtr.Zero) NativeMethods.ReleaseDC(IntPtr.Zero, screenDC);
        }
    }
}
