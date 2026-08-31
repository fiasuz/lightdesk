import SwiftUI

struct HomeView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 24) {
            Text("LiteDesk").font(.system(size: 22, weight: .semibold))
            Text("Internet orqali masofadan boshqarish")
                .font(.system(size: 13))
                .foregroundColor(Palette.subtitle)
            HStack(spacing: 16) {
                ModeButton(icon: "🖥️", title: "Bu kompyuterni ulashish", subtitle: "(Host bo'lish)") {
                    appState.mode = .host
                }
                ModeButton(icon: "🔗", title: "Boshqa kompyuterga ulanish", subtitle: "(Viewer)") {
                    appState.mode = .viewer
                }
            }
        }
        .padding(24)
    }
}

private struct ModeButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Text(icon).font(.system(size: 30))
                Text(title).multilineTextAlignment(.center)
                Text(subtitle).font(.system(size: 12)).foregroundColor(Palette.subtitle)
            }
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .background(Palette.card)
        .cornerRadius(12)
    }
}
