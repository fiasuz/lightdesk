using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;

namespace LiteDesk.Native;

// Minimal RFC 6455 (section 4.2.2) server-side HTTP Upgrade handshake, done
// by hand over a raw NetworkStream so the host can bind with a plain
// TcpListener instead of HttpListener (HttpListener needs a urlacl
// reservation or admin elevation to bind a non-loopback prefix, which would
// regress the current app's "no admin needed to host" behavior).
public static class WebSocketHandshake
{
    private const string WebSocketGuid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
    private const int MaxHeaderBytes = 16 * 1024;

    // Reads the HTTP upgrade request off the stream and writes the
    // "101 Switching Protocols" response. Returns true if the handshake
    // completed and the stream is now ready for
    // WebSocket.CreateFromStream(stream, isServer: true, ...); false if the
    // peer didn't send a valid WebSocket upgrade request (caller should
    // close the connection).
    public static async Task<bool> PerformServerHandshakeAsync(NetworkStream stream, CancellationToken ct)
    {
        string request = await ReadHttpHeadersAsync(stream, ct).ConfigureAwait(false);
        if (string.IsNullOrEmpty(request)) return false;

        string? key = ExtractHeaderValue(request, "Sec-WebSocket-Key");
        if (string.IsNullOrEmpty(key)) return false;

        string acceptKey = ComputeAcceptKey(key);

        string response =
            "HTTP/1.1 101 Switching Protocols\r\n" +
            "Upgrade: websocket\r\n" +
            "Connection: Upgrade\r\n" +
            $"Sec-WebSocket-Accept: {acceptKey}\r\n\r\n";

        byte[] responseBytes = Encoding.ASCII.GetBytes(response);
        await stream.WriteAsync(responseBytes, ct).ConfigureAwait(false);
        return true;
    }

    // Headers are small and arrive in one shot from a WebSocket client, so a
    // simple byte-at-a-time scan for the blank-line terminator is sufficient
    // here — no need for a general HTTP parser.
    private static async Task<string> ReadHttpHeadersAsync(NetworkStream stream, CancellationToken ct)
    {
        var buffer = new List<byte>(1024);
        var single = new byte[1];

        while (buffer.Count < MaxHeaderBytes)
        {
            int read = await stream.ReadAsync(single, ct).ConfigureAwait(false);
            if (read == 0) break; // peer closed before completing the request

            buffer.Add(single[0]);
            int c = buffer.Count;
            if (c >= 4 &&
                buffer[c - 4] == (byte)'\r' && buffer[c - 3] == (byte)'\n' &&
                buffer[c - 2] == (byte)'\r' && buffer[c - 1] == (byte)'\n')
            {
                break;
            }
        }

        return Encoding.ASCII.GetString(buffer.ToArray());
    }

    private static string? ExtractHeaderValue(string request, string headerName)
    {
        foreach (string rawLine in request.Split("\r\n"))
        {
            int colon = rawLine.IndexOf(':');
            if (colon < 0) continue;

            string name = rawLine[..colon].Trim();
            if (string.Equals(name, headerName, StringComparison.OrdinalIgnoreCase))
            {
                return rawLine[(colon + 1)..].Trim();
            }
        }
        return null;
    }

    private static string ComputeAcceptKey(string secWebSocketKey)
    {
        byte[] combined = Encoding.ASCII.GetBytes(secWebSocketKey + WebSocketGuid);
        byte[] hash = SHA1.HashData(combined);
        return Convert.ToBase64String(hash);
    }
}
