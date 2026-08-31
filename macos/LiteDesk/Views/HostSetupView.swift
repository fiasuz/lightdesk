import SwiftUI
import AppKit

struct HostSetupView: View {
    @ObservedObject var session: HostSession
    @State private var password: String = Self.generatePin()

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 4) {
                Text("Bu kompyuterni ulashish").font(.system(size: 22, weight: .semibold))
                Text("Boshqa kompyuter shu manzil va parol orqali ulanadi")
                    .font(.system(size: 13))
                    .foregroundColor(Palette.subtitle)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 14) {
                FormField(label: "Parol (PIN)") {
                    Text(password)
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .tracking(4)
                        .foregroundColor(Palette.accent)
                }

                if !session.permissions.allGranted {
                    Text("macOS: Ekran yozish va Accessibility ruxsatlarini bering (Tizim sozlamalari > Maxfiylik va xavfsizlik), so'ng ilovani qayta ishga tushiring.")
                        .foregroundColor(Palette.err)
                        .font(.system(size: 13))
                }

                if let error = session.errorMessage {
                    Text(error).foregroundColor(Palette.err).font(.system(size: 13))
                }

                Button("Ulashishni boshlash") {
                    session.start(password: password)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
            .padding(24)
            .background(Palette.card)
            .cornerRadius(12)
            .frame(width: 380)
        }
        .padding(24)
        .onAppear {
            session.refreshPermissions()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            session.refreshPermissions()
        }
    }

    private static func generatePin() -> String {
        String(format: "%06d", Int.random(in: 100_000...999_999))
    }
}
