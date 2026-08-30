import SwiftUI

private enum ConnectionMode: String, CaseIterable, Identifiable {
    case lan = "LAN"
    case internet = "Internet"
    var id: String { rawValue }
}

struct ViewerSetupView: View {
    @ObservedObject var session: ViewerSession
    @State private var mode: ConnectionMode = .lan
    @State private var ip: String = ""
    @State private var port: String = "5900"
    @State private var tunnelAddress: String = ""
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
                Picker("", selection: $mode) {
                    ForEach(ConnectionMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if mode == .lan {
                    FormField(label: "IP manzil") {
                        TextField("masalan: 192.168.1.24", text: $ip).textFieldStyle(.roundedBorder)
                    }
                    FormField(label: "Port") {
                        TextField("", text: $port).textFieldStyle(.roundedBorder)
                    }
                } else {
                    FormField(label: "Tunnel manzili") {
                        TextField("masalan: xxxx.trycloudflare.com", text: $tunnelAddress)
                            .textFieldStyle(.roundedBorder)
                    }
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
        let trimmedPassword = password.trimmingCharacters(in: .whitespaces)
        guard !trimmedPassword.isEmpty else {
            statusText = "Parolni kiriting"
            return
        }

        let resolvedIp: String
        let resolvedPort: Int?
        let useTLS: Bool

        switch mode {
        case .lan:
            let trimmedIp = ip.trimmingCharacters(in: .whitespaces)
            guard !trimmedIp.isEmpty else {
                statusText = "IP manzilni kiriting"
                return
            }
            resolvedIp = trimmedIp
            resolvedPort = Int(port) ?? 5900
            useTLS = false
        case .internet:
            let cleanedAddress = Self.stripSchemeAndSlashes(tunnelAddress)
            guard !cleanedAddress.isEmpty else {
                statusText = "Tunnel manzilini kiriting"
                return
            }
            resolvedIp = cleanedAddress
            resolvedPort = nil
            useTLS = true
        }

        isConnecting = true
        statusText = ""
        session.connect(ip: resolvedIp, port: resolvedPort, useTLS: useTLS, password: trimmedPassword) { success, error in
            isConnecting = false
            if !success {
                statusText = "Xato: " + (error ?? "")
            }
        }
    }

    /// Lets the user paste a full URL (`https://xxxx.trycloudflare.com`) or
    /// just the bare hostname — both should work.
    private static func stripSchemeAndSlashes(_ raw: String) -> String {
        var address = raw.trimmingCharacters(in: .whitespaces)
        for prefix in ["https://", "wss://", "http://", "ws://"] where address.hasPrefix(prefix) {
            address.removeFirst(prefix.count)
        }
        return address.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
