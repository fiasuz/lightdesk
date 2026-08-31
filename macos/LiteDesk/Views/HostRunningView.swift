import SwiftUI
import AppKit

struct HostRunningView: View {
    @ObservedObject var session: HostSession

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Text("PIN").font(.system(size: 12)).foregroundColor(Palette.subtitle)
                    Text(session.pin)
                        .font(.system(size: 30, weight: .bold))
                        .tracking(6)
                        .foregroundColor(Palette.accent)
                }

                tunnelSection

                Text(session.viewerConnected
                     ? "Ulandi — masofaviy foydalanuvchi sichqonchani boshqarmoqda"
                     : "Ulanish kutilmoqda...")
                    .font(.system(size: 13))
                    .foregroundColor(session.viewerConnected ? Palette.ok : Palette.subtitle)

                Button("To'xtatish") {
                    session.stop()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
            .padding(24)
            .background(Palette.card)
            .cornerRadius(12)
            .frame(width: 380)
        }
        .padding(24)
    }

    @ViewBuilder
    private var tunnelSection: some View {
        switch session.tunnelState {
        case .idle:
            EmptyView()
        case .starting:
            Text("Internet tunnel ochilmoqda...")
                .font(.system(size: 12))
                .foregroundColor(Palette.subtitle)
        case .running(let url):
            let code = Self.connectionCode(pin: session.pin, tunnelURL: url)
            VStack(spacing: 6) {
                Text("Internet orqali ulanish kodi").font(.system(size: 12)).foregroundColor(Palette.subtitle)
                Text(code)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Palette.accent)
                    .textSelection(.enabled)
                Button("Nusxalash") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(code, forType: .string)
                }
                .buttonStyle(.link)
                .font(.system(size: 12))
            }
        case .failed(let message):
            Text("Internet tunnel xatosi: \(message)")
                .font(.system(size: 12))
                .foregroundColor(Palette.err)
        }
    }

    /// Bundles the PIN and tunnel host into the single code the viewer's
    /// "Ulanish kodi" field parses (see `ViewerSetupView.parseConnectionCode`)
    /// — the viewer no longer needs the raw tunnel link pasted separately.
    /// The `.trycloudflare.com` suffix is stripped here (and re-added by the
    /// viewer when parsing) purely to keep the shared code shorter/cleaner —
    /// it's implied since every quick tunnel uses that domain.
    private static func connectionCode(pin: String, tunnelURL: String) -> String {
        var host = tunnelURL
        for prefix in ["https://", "http://"] where host.hasPrefix(prefix) {
            host.removeFirst(prefix.count)
        }
        host = host.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if host.hasSuffix(ViewerSetupView.tunnelDomainSuffix) {
            host.removeLast(ViewerSetupView.tunnelDomainSuffix.count)
        }
        return "\(pin)-\(host)"
    }
}
