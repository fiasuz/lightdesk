import SwiftUI
import AppKit

struct HostRunningView: View {
    @ObservedObject var session: HostSession

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                Text(ipListText)
                    .font(.system(size: 13))
                    .foregroundColor(Palette.subtitle)
                    .multilineTextAlignment(.center)

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

    private var ipListText: String {
        let base = session.localIPs.isEmpty
            ? "IP manzil topilmadi"
            : session.localIPs.joined(separator: ", ") + " manzillaridan biri"
        return base + " (port: \(session.port))"
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
            VStack(spacing: 6) {
                Text("Internet orqali manzil").font(.system(size: 12)).foregroundColor(Palette.subtitle)
                Text(url)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Palette.accent)
                    .textSelection(.enabled)
                Button("Nusxalash") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(url, forType: .string)
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
}
