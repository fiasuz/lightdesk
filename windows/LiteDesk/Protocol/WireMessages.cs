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
