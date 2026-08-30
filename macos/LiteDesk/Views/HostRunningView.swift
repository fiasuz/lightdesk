import SwiftUI

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
        session.localIPs.isEmpty
            ? "IP manzil topilmadi"
            : session.localIPs.joined(separator: ", ") + " manzillaridan biri"
    }
}
