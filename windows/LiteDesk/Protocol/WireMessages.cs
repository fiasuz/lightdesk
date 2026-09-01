using System.Text.Json.Serialization;

namespace LiteDesk.Protocol;

// Wire-format POCOs. Field names/casing are pinned with [JsonPropertyName] to
// stay byte-for-byte compatible with the existing Electron app's protocol
// (see src/main.js and src/renderer/viewer.js) and with the parallel native
// macOS app, so a Windows host can interoperate with a macOS viewer and vice
// versa over plain ws://.

public abstract class WireMessage
{
    [JsonPropertyName("type")]
    public string Type { get; protected set; } = "";
}

public sealed class AuthMessage : WireMessage
{
    public AuthMessage() { Type = "auth"; }

    [JsonPropertyName("password")]
    public string Password { get; set; } = "";
}

public sealed class AuthOkMessage : WireMessage
{
    public AuthOkMessage() { Type = "auth-ok"; }

    [JsonPropertyName("width")]
    public int Width { get; set; }

    [JsonPropertyName("height")]
    public int Height { get; set; }
}

public sealed class AuthFailMessage : WireMessage
{
    public AuthFailMessage() { Type = "auth-fail"; }
}

public sealed class MouseMoveMessage : WireMessage
{
    public MouseMoveMessage() { Type = "mouse-move"; }

    [JsonPropertyName("x")]
    public double X { get; set; }

    [JsonPropertyName("y")]
    public double Y { get; set; }
}

public sealed class MouseDownMessage : WireMessage
{
    public MouseDownMessage() { Type = "mouse-down"; }

    [JsonPropertyName("x")]
    public double X { get; set; }

    [JsonPropertyName("y")]
    public double Y { get; set; }

    [JsonPropertyName("button")]
    public string Button { get; set; } = "left";
}

public sealed class MouseUpMessage : WireMessage
{
    public MouseUpMessage() { Type = "mouse-up"; }

    [JsonPropertyName("button")]
    public string Button { get; set; } = "left";
}

public sealed class MouseScrollMessage : WireMessage
{
    public MouseScrollMessage() { Type = "mouse-scroll"; }

    [JsonPropertyName("dx")]
    public double Dx { get; set; }

    [JsonPropertyName("dy")]
    public double Dy { get; set; }
}

// `Code` is a layout-independent physical-key identifier using the W3C
// UIEvents KeyboardEvent.code vocabulary (e.g. "KeyA", "ShiftLeft",
// "ArrowLeft") so a Windows viewer can drive a macOS host and vice versa
// without either side knowing the other's native keycode space — see
// Native/KeyCodeMap.cs for the translation table.
public sealed class KeyDownMessage : WireMessage
{
    public KeyDownMessage() { Type = "key-down"; }

    [JsonPropertyName("code")]
    public string Code { get; set; } = "";
}

public sealed class KeyUpMessage : WireMessage
{
    public KeyUpMessage() { Type = "key-up"; }

    [JsonPropertyName("code")]
    public string Code { get; set; } = "";
}

// Bidirectional keepalive/latency probe: either side may send a ping at any
// time; the other side replies with a pong echoing the same `ts` unchanged,
// so the sender can compute round-trip time as (now - ts). `ts` is Unix
// epoch seconds (a double, sub-second precision) — must match the macOS
// app's Date().timeIntervalSince1970 encoding byte-for-byte.
public sealed class PingMessage : WireMessage
{
    public PingMessage() { Type = "ping"; }

    [JsonPropertyName("ts")]
    public double Ts { get; set; }
}

public sealed class PongMessage : WireMessage
{
    public PongMessage() { Type = "pong"; }

    [JsonPropertyName("ts")]
    public double Ts { get; set; }
}
