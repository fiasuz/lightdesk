import Foundation

/// Spawns and supervises a bundled `cloudflared` subprocess to expose the
/// host's local WebSocket server via a free Cloudflare Quick Tunnel, so a
/// viewer outside the LAN can connect via a public `*.trycloudflare.com`
/// URL — no router/port-forwarding, no paid relay server.
final class CloudflaredTunnelManager: ObservableObject {
    enum TunnelState: Equatable {
        case idle
        case starting
        case running(url: String)
        case failed(String)
    }

    // Weak registry of every manager with a live process, so the app can
    // force-kill them all on quit (Process does not auto-terminate its
    // children when the parent app exits — an unmanaged cloudflared would
    // otherwise leak as an orphan).
    private static let activeManagers = NSHashTable<CloudflaredTunnelManager>.weakObjects()

    static func stopAll() {
        for manager in activeManagers.allObjects {
            manager.stop()
        }
    }

    @Published private(set) var state: TunnelState = .idle

    private var process: Process?
    private var stderrPipe: Pipe?
    private var outputBuffer = Data()

    func start(port: UInt16) {
        guard case .idle = state else { return }
        guard let binaryURL = Self.resolveBinaryURL() else {
            state = .failed("cloudflared topilmadi")
            return
        }

        state = .starting

        let process = Process()
        process.executableURL = binaryURL
        process.arguments = ["tunnel", "--url", "http://localhost:\(port)", "--no-autoupdate"]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        // cloudflared writes its "here's your URL" banner to stderr; stdout
        // is unused but must still be drained somewhere or the pipe buffer
        // can fill and stall the child process.
        process.standardOutput = FileHandle.nullDevice

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.consume(data)
        }

        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self else { return }
                switch self.state {
                case .running:
                    self.state = .failed("Tunnel uzildi")
                case .starting:
                    self.state = .failed("cloudflared ishga tushmadi (kod \(proc.terminationStatus))")
                default:
                    break
                }
            }
        }

        do {
            try process.run()
            self.process = process
            self.stderrPipe = stderrPipe
            Self.activeManagers.add(self)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stop() {
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminationHandler = nil
        if process?.isRunning == true {
            process?.terminate()
        }
        process = nil
        stderrPipe = nil
        outputBuffer.removeAll()
        Self.activeManagers.remove(self)
        if state != .idle {
            state = .idle
        }
    }

    // MARK: - Output parsing

    private func consume(_ data: Data) {
        outputBuffer.append(data)
        guard let text = String(data: outputBuffer, encoding: .utf8) else { return }
        guard let url = Self.extractTunnelURL(from: text) else { return }
        // Found it — no need to keep buffering further output.
        outputBuffer.removeAll()
        DispatchQueue.main.async { [weak self] in
            guard let self, case .running = self.state else {
                self?.state = .running(url: url)
                return
            }
        }
    }

    // MARK: - Pure, unit-testable helpers

    /// Extracts the first `https://<subdomain>.trycloudflare.com` URL found
    /// in a chunk of cloudflared log output (stderr).
    static func extractTunnelURL(from text: String) -> String? {
        let pattern = #"https://[a-zA-Z0-9-]+\.trycloudflare\.com"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let matchRange = Range(match.range, in: text) else {
            return nil
        }
        return String(text[matchRange])
    }

    /// Resolves the `cloudflared` binary to run: prefers the copy bundled
    /// inside the app (`Contents/Resources/cloudflared`, added by
    /// Packaging/build-app.sh), then falls back to common Homebrew install
    /// locations and finally a PATH lookup — useful when running via
    /// `swift run` in development, where there is no app bundle.
    static func resolveBinaryURL() -> URL? {
        var candidates: [URL] = []
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("cloudflared"))
        }
        candidates.append(URL(fileURLWithPath: "/opt/homebrew/bin/cloudflared"))
        candidates.append(URL(fileURLWithPath: "/usr/local/bin/cloudflared"))

        for url in candidates where FileManager.default.isExecutableFile(atPath: url.path) {
            return url
        }

        if let pathHit = lookUpInPath("cloudflared") {
            return URL(fileURLWithPath: pathHit)
        }
        return nil
    }

    private static func lookUpInPath(_ name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty else {
            return nil
        }
        return output
    }
}
