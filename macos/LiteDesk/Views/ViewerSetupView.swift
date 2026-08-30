import SwiftUI

struct ViewerSetupView: View {
    @ObservedObject var session: ViewerSession
    @State private var ip: String = ""
    @State private var port: String = "5900"
    @State private var password: String = ""
    @State private var statusText: String = ""
    @State private var isConnecting = false

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 4) {
                Text("Boshqa kompyuterga ulanish").font(.system(size: 22, weight: .semibold))
                Text("Ulanmoqchi bo'lgan kompyuterning IP manzili va parolini kiriting")
                    .font(.system(size: 13))
                    .foregroundColor(Palette.subtitle)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 14) {
                FormField(label: "IP manzil") {
                    TextField("masalan: 192.168.1.24", text: $ip).textFieldStyle(.roundedBorder)
                }
                FormField(label: "Port") {
                    TextField("", text: $port).textFieldStyle(.roundedBorder)
                }
                FormField(label: "Parol (PIN)") {
                    TextField("", text: $password).textFieldStyle(.roundedBorder)
                }

                if !statusText.isEmpty {
                    Text(statusText).font(.system(size: 13)).foregroundColor(Palette.err)
                }

                Button(isConnecting ? "Ulanmoqda..." : "Ulanish") {
                    connect()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(isConnecting)
            }
            .padding(24)
            .background(Palette.card)
            .cornerRadius(12)
            .frame(width: 380)
        }
        .padding(24)
    }

    private func connect() {
        let trimmedIp = ip.trimmingCharacters(in: .whitespaces)
        let trimmedPassword = password.trimmingCharacters(in: .whitespaces)
        guard !trimmedIp.isEmpty, !trimmedPassword.isEmpty else {
            statusText = "IP va parolni kiriting"
            return
        }
        isConnecting = true
        statusText = ""
        session.connect(ip: trimmedIp, port: Int(port) ?? 5900, password: trimmedPassword) { success, error in
            isConnecting = false
            if !success {
                statusText = "Xato: " + (error ?? "")
            }
        }
    }
}
