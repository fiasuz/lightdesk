import SwiftUI
import AppKit

struct HostSetupView: View {
    @ObservedObject var session: HostSession
    @State private var port: String = "5900"
    @State private var password: String = String(format: "%06d", Int.random(in: 100_000...999_999))
    @State private var useTunnel: Bool = false

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
                FormField(label: "Port") {
                    TextField("", text: $port).textFieldStyle(.roundedBorder)
                }
                FormField(label: "Parol (PIN)") {
                    TextField("", text: $password).textFieldStyle(.roundedBorder)
                }

                Toggle("Internet orqali ham ulash (Cloudflare Tunnel)", isOn: $useTunnel)
                    .toggleStyle(.checkbox)
                Text("Boshqa tarmoqdagi qurilma ham ulana oladi — bepul, router sozlash shart emas.")
                    .font(.system(size: 11))
                    .foregroundColor(Palette.subtitle)

                if !session.permissions.allGranted {
                    Text("macOS: Ekran yozish va Accessibility ruxsatlarini bering (Tizim sozlamalari > Maxfiylik va xavfsizlik), so'ng ilovani qayta ishga tushiring.")
                        .foregroundColor(Palette.err)
                        .font(.system(size: 13))
                }

                if let error = session.errorMessage {
                    Text(error).foregroundColor(Palette.err).font(.system(size: 13))
                }

                Button("Ulashishni boshlash") {
                    let portNumber = UInt16(port) ?? 5900
                    session.start(port: portNumber, password: password, useTunnel: useTunnel)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(password.trimmingCharacters(in: .whitespaces).isEmpty)
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
}
