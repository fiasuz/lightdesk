using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Channels;
using System.Threading.Tasks;
using LiteDesk.Native;
using LiteDesk.Protocol;

namespace LiteDesk.Services;

// Injects real OS-level mouse events via SendInput. Incoming messages are
// serialized through a single-reader Channel so they apply in strict
// arrival order — a native equivalent of the Electron app's
// `mouseQueue = mouseQueue.then(...)` promise chain (src/main.js).
public sealed class MouseInjector
{
    private static readonly int InputSize = Marshal.SizeOf<NativeMethods.INPUT>();

    private readonly Channel<WireMessage> _channel = Channel.CreateUnbounded<WireMessage>(
        new UnboundedChannelOptions { SingleReader = true, SingleWriter = false });

    private CancellationTokenSource? _cts;
    private Task? _worker;

    // Set by HostServer from ScreenCapture.GetPrimaryMonitorSize() when a
    // viewer connects — the same pixel size Phase 3 captures, so incoming
    // 0..1 normalized coordinates scale against exactly the region the
    // viewer is actually looking at.
    public int FrameWidth { get; set; }
    public int FrameHeight { get; set; }

    public void Start()
    {
        if (_worker is not null) return;
        _cts = new CancellationTokenSource();
        _worker = Task.Run(() => RunAsync(_cts.Token));
    }

    public void Stop()
    {
        _cts?.Cancel();
        _cts = null;
        _worker = null;
    }

    public void Enqueue(WireMessage message) => _channel.Writer.TryWrite(message);

    private async Task RunAsync(CancellationToken ct)
    {
        try
        {
            await foreach (WireMessage msg in _channel.Reader.ReadAllAsync(ct).ConfigureAwait(false))
            {
                try
                {
                    Apply(msg);
                }
                catch
                {
                    // A single malformed/out-of-range event shouldn't stop
                    // the injector from processing the rest of the session.
                }
            }
        }
        catch (OperationCanceledException)
        {
            // Normal on Stop().
        }
    }

    private void Apply(WireMessage msg)
    {
        switch (msg)
        {
            case MouseMoveMessage move:
                MoveTo(move.X, move.Y);
                break;

            case MouseDownMessage down:
                // Two separate SendInput calls — move then click — mirrors
                // src/mouseControl.js's `move(x, y); down(button);`
                // sequence exactly.
                MoveTo(down.X, down.Y);
                ButtonEvent(down.Button, isDown: true);
                break;

            case MouseUpMessage up:
                ButtonEvent(up.Button, isDown: false);
                break;

            case MouseScrollMessage scroll:
                Scroll(scroll.Dx, scroll.Dy);
                break;
        }
    }

    private void MoveTo(double normalizedX, double normalizedY)
    {
        if (FrameWidth <= 0 || FrameHeight <= 0) return;

        double px = Clamp01(normalizedX) * FrameWidth;
        double py = Clamp01(normalizedY) * FrameHeight;

        // Capture is primary-monitor-only, and the primary monitor's
        // top-left is always (0,0) in Windows' virtual-desktop coordinate
        // space, so px/py are already absolute desktop pixel coordinates —
        // no per-monitor offset translation is needed before this step.
        // They still need to be renormalized into MOUSEEVENTF_ABSOLUTE's
        // 0..65535 space against the *virtual desktop* bounds (not just the
        // primary monitor), which is what MOUSEEVENTF_VIRTUALDESK expects.
        int virtualLeft = NativeMethods.GetSystemMetrics(NativeMethods.SM_XVIRTUALSCREEN);
        int virtualTop = NativeMethods.GetSystemMetrics(NativeMethods.SM_YVIRTUALSCREEN);
        int virtualWidth = NativeMethods.GetSystemMetrics(NativeMethods.SM_CXVIRTUALSCREEN);
        int virtualHeight = NativeMethods.GetSystemMetrics(NativeMethods.SM_CYVIRTUALSCREEN);
        if (virtualWidth <= 0 || virtualHeight <= 0) return;

        int normX = (int)Math.Round((px - virtualLeft) * 65536.0 / virtualWidth);
        int normY = (int)Math.Round((py - virtualTop) * 65536.0 / virtualHeight);

        SendSingleInput(new NativeMethods.INPUT
        {
            type = NativeMethods.INPUT_MOUSE,
            mi = new NativeMethods.MOUSEINPUT
            {
                dx = normX,
                dy = normY,
                mouseData = 0,
                dwFlags = NativeMethods.MOUSEEVENTF_MOVE | NativeMethods.MOUSEEVENTF_ABSOLUTE | NativeMethods.MOUSEEVENTF_VIRTUALDESK,
                time = 0,
                dwExtraInfo = IntPtr.Zero,
            },
        });
    }

    private void ButtonEvent(string button, bool isDown)
    {
        uint flag = button switch
        {
            "right" => isDown ? NativeMethods.MOUSEEVENTF_RIGHTDOWN : NativeMethods.MOUSEEVENTF_RIGHTUP,
            "middle" => isDown ? NativeMethods.MOUSEEVENTF_MIDDLEDOWN : NativeMethods.MOUSEEVENTF_MIDDLEUP,
            _ => isDown ? NativeMethods.MOUSEEVENTF_LEFTDOWN : NativeMethods.MOUSEEVENTF_LEFTUP,
        };

        // No ABSOLUTE flag and dx=dy=0: registers the click at wherever the
        // immediately-preceding move call already placed the cursor.
        SendSingleInput(new NativeMethods.INPUT
        {
            type = NativeMethods.INPUT_MOUSE,
            mi = new NativeMethods.MOUSEINPUT
            {
                dx = 0,
                dy = 0,
                mouseData = 0,
                dwFlags = flag,
                time = 0,
                dwExtraInfo = IntPtr.Zero,
            },
        });
    }

    private void Scroll(double dx, double dy)
    {
        // mouseData sign convention here is taken as given by the plan
        // (sign(delta) * clamped * WHEEL_DELTA, no inversion) — this is the
        // one part of this file that most needs empirical verification on
        // real hardware, since Win32's "positive = wheel rotated forward /
        // away from user" convention does not obviously match the sign of
        // a browser `wheel` event's deltaY that src/mouseControl.js was
        // written against. See the completion report for this flag.
        if (dy != 0)
        {
            int clamped = (int)Math.Min(Math.Abs(dy), 50);
            SendWheel(NativeMethods.MOUSEEVENTF_WHEEL, Math.Sign(dy) * clamped * NativeMethods.WHEEL_DELTA);
        }
        if (dx != 0)
        {
            int clamped = (int)Math.Min(Math.Abs(dx), 50);
            SendWheel(NativeMethods.MOUSEEVENTF_HWHEEL, Math.Sign(dx) * clamped * NativeMethods.WHEEL_DELTA);
        }
    }

    private void SendWheel(uint flag, int amount)
    {
        SendSingleInput(new NativeMethods.INPUT
        {
            type = NativeMethods.INPUT_MOUSE,
            mi = new NativeMethods.MOUSEINPUT
            {
                dx = 0,
                dy = 0,
                mouseData = unchecked((uint)amount),
                dwFlags = flag,
                time = 0,
                dwExtraInfo = IntPtr.Zero,
            },
        });
    }

    private static void SendSingleInput(NativeMethods.INPUT input)
    {
        var inputs = new[] { input };
        NativeMethods.SendInput(1, inputs, InputSize);
    }

    private static double Clamp01(double v) => Math.Min(Math.Max(v, 0), 1);
}
