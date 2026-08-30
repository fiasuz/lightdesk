using System.Text.Json;

namespace LiteDesk.Protocol;

// Reads the "type" discriminator out of an incoming JSON text message and
// deserializes into the matching WireMessage subclass. Shared by HostServer
// (host-side, receives auth/mouse-*) and ViewerClient (viewer-side, receives
// auth-ok/auth-fail).
public static class WireMessageParser
{
    public static WireMessage? TryParse(string json)
    {
        try
        {
            using JsonDocument doc = JsonDocument.Parse(json);
            if (!doc.RootElement.TryGetProperty("type", out JsonElement typeEl)) return null;

            return typeEl.GetString() switch
            {
                "auth" => JsonSerializer.Deserialize<AuthMessage>(json),
                "auth-ok" => JsonSerializer.Deserialize<AuthOkMessage>(json),
                "auth-fail" => JsonSerializer.Deserialize<AuthFailMessage>(json),
                "mouse-move" => JsonSerializer.Deserialize<MouseMoveMessage>(json),
                "mouse-down" => JsonSerializer.Deserialize<MouseDownMessage>(json),
                "mouse-up" => JsonSerializer.Deserialize<MouseUpMessage>(json),
                "mouse-scroll" => JsonSerializer.Deserialize<MouseScrollMessage>(json),
                _ => null,
            };
        }
        catch (JsonException)
        {
            return null;
        }
    }
}
