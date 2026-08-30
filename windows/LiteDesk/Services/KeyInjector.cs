using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Channels;
using System.Threading.Tasks;
using LiteDesk.Native;
using LiteDesk.Protocol;

namespace LiteDesk.Services;

// Injects real OS-level keyboard events via SendInput, mirroring
// MouseInjector's single-reader Channel design so key and mouse messages
// from the same viewer apply in the order they were sent.
public sealed class KeyInjector
{
    private static readonly int InputSize = Marshal.SizeOf<NativeMethods.INPUT>();

    private readonly Channel<WireMessage> _channel = Channel.CreateUnbounded<WireMessage>(
        new UnboundedChannelOptions { SingleReader = true, SingleWriter = false });

    private CancellationTokenSource? _cts;
    private Task? _worker;

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
            case KeyDownMessage down:
                SendKey(down.Code, isDown: true);
                break;

            case KeyUpMessage up:
                SendKey(up.Code, isDown: false);
                break;
        }
    }

    private void SendKey(string code, bool isDown)
    {
        ushort? vk = KeyCodeMap.VirtualKey(code);
        if (vk is null) return; // unrecognized code — nothing sane to inject

        var input = new NativeMethods.INPUT
        {
            type = NativeMethods.INPUT_KEYBOARD,
            ki = new NativeMethods.KEYBDINPUT
            {
                wVk = vk.Value,
                wScan = 0,
                dwFlags = isDown ? 0 : NativeMethods.KEYEVENTF_KEYUP,
                time = 0,
                dwExtraInfo = IntPtr.Zero,
            },
        };

        var inputs = new[] { input };
        NativeMethods.SendInput(1, inputs, InputSize);
    }
}
