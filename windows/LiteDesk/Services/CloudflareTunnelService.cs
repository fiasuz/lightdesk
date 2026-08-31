using System;
using System.Diagnostics;
using System.IO;
using System.Text.RegularExpressions;

namespace LiteDesk.Services;

public enum TunnelStatus
{
    Idle,
    Starting,
    Running,
    Failed,
}

// Immutable status + payload pair reported by CloudflareTunnelService. Only
// Url is set when Status == Running; only Error is set when Status == Failed.
public sealed class TunnelState
{
    public TunnelStatus Status { get; }
    public string? Url { get; }
    public string? Error { get; }

    private TunnelState(TunnelStatus status, string? url, string? error)
    {
        Status = status;
        Url = url;
        Error = error;
    }

    public static readonly TunnelState Idle = new(TunnelStatus.Idle, null, null);
    public static readonly TunnelState Starting = new(TunnelStatus.Starting, null, null);
    public static TunnelState Running(string url) => new(TunnelStatus.Running, url, null);
    public static TunnelState Failed(string error) => new(TunnelStatus.Failed, null, error);
}

// Wraps a bundled `cloudflared` "quick tunnel" so the host's local WebSocket
// server becomes reachable from the public internet without any router
// port-forwarding: cloudflared opens an outbound connection to Cloudflare's
// edge, which hands back a random *.trycloudflare.com URL that proxies
// straight through to http://localhost:<port>. No Cloudflare account or
// paid relay server needed.
public sealed class CloudflareTunnelService
{
    private static readonly Regex TunnelUrlPattern =
        new(@"https://[a-z0-9-]+\.trycloudflare\.com", RegexOptions.Compiled);

    private Process? _process;
    private bool _urlReported;

    public event Action<TunnelState>? StateChanged;

    // Pure/testable: extracts a quick-tunnel URL from one line of cloudflared
    // output (it prints the assigned URL to stderr), or null if absent.
    public static string? TryExtractTunnelUrl(string line)
    {
        Match match = TunnelUrlPattern.Match(line);
        return match.Success ? match.Value : null;
    }

    // Prefers the binary bundled next to LiteDesk.exe (see the
    // EnsureCloudflared MSBuild target in LiteDesk.csproj); falls back to
    // PATH for a manually-installed cloudflared during development.
    public static string? ResolveCloudflaredPath()
    {
        string bundled = Path.Combine(AppContext.BaseDirectory, "cloudflared.exe");
        if (File.Exists(bundled)) return bundled;

        string? pathEnv = Environment.GetEnvironmentVariable("PATH");
        if (pathEnv is null) return null;

        foreach (string dir in pathEnv.Split(Path.PathSeparator))
        {
            string candidate;
            try
            {
                candidate = Path.Combine(dir, "cloudflared.exe");
            }
            catch
            {
                continue; // malformed PATH entry
            }

            if (File.Exists(candidate)) return candidate;
        }

        return null;
    }

    public void Start(int port)
    {
        Stop();

        string? exePath = ResolveCloudflaredPath();
        if (exePath is null)
        {
            StateChanged?.Invoke(TunnelState.Failed("cloudflared.exe topilmadi"));
            return;
        }

        StateChanged?.Invoke(TunnelState.Starting);
        _urlReported = false;

        var startInfo = new ProcessStartInfo
        {
            FileName = exePath,
            Arguments = $"tunnel --url http://localhost:{port} --no-autoupdate",
            RedirectStandardError = true,
            RedirectStandardOutput = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };

        var process = new Process { StartInfo = startInfo, EnableRaisingEvents = true };
        process.ErrorDataReceived += (_, e) => OnLineReceived(e.Data);
        process.OutputDataReceived += (_, e) => OnLineReceived(e.Data);

        try
        {
            process.Start();
        }
        catch (Exception ex)
        {
            process.Dispose();
            StateChanged?.Invoke(TunnelState.Failed(ex.Message));
            return;
        }

        _process = process;
        process.BeginErrorReadLine();
        process.BeginOutputReadLine();
    }

    // cloudflared quick tunnels print the assigned URL on stderr, framed by
    // a decorative box (see cloudflared's "Your quick Tunnel has been
    // created!" banner) — scan every line rather than assuming a fixed
    // position, and only report the first match per Start().
    private void OnLineReceived(string? line)
    {
        if (line is null || _urlReported) return;

        string? url = TryExtractTunnelUrl(line);
        if (url is null) return;

        _urlReported = true;
        StateChanged?.Invoke(TunnelState.Running(url));
    }

    public void Stop()
    {
        _urlReported = false;

        Process? process = _process;
        _process = null;
        if (process is null) return;

        try
        {
            if (!process.HasExited) process.Kill(entireProcessTree: true);
        }
        catch
        {
            // Already exited or inaccessible; nothing more to do.
        }
        finally
        {
            process.Dispose();
        }
    }
}
