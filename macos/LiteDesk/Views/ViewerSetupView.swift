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
                }
                FormField(label: mode == .lan ? "Parol (PIN)" : "Ulanish kodi") {
                    TextField(mode == .lan ? "" : "masalan: 123456-xxxx", text: $password)
                        .textFieldStyle(.roundedBorder)
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
        let resolvedIp: String
        let resolvedPort: Int?
        let useTLS: Bool
        let authPassword: String

        switch mode {
        case .lan:
            let trimmedIp = ip.trimmingCharacters(in: .whitespaces)
            guard !trimmedIp.isEmpty else {
                statusText = "IP manzilni kiriting"
                return
            }
            let trimmedPassword = password.trimmingCharacters(in: .whitespaces)
            guard !trimmedPassword.isEmpty else {
                statusText = "Parolni kiriting"
                return
            }
            resolvedIp = trimmedIp
            resolvedPort = Int(port) ?? 5900
            useTLS = false
            authPassword = trimmedPassword
        case .internet:
            guard let parsed = Self.parseConnectionCode(password) else {
                statusText = "Kodni tekshiring — to'liq ulanish kodini kiriting"
                return
            }
            resolvedIp = parsed.host
            resolvedPort = nil
            useTLS = true
            authPassword = parsed.pin
        }

        isConnecting = true
        statusText = ""
        session.connect(ip: resolvedIp, port: resolvedPort, useTLS: useTLS, password: authPassword) { success, error in
            isConnecting = false
            if !success {
                statusText = "Xato: " + (error ?? "")
            }
        }
    }

    /// Every Cloudflare quick tunnel lives under this domain — the host
    /// strips it off the shared code (see `HostRunningView.connectionCode`)
    /// so the user never sees it, and it's re-added here.
    static let tunnelDomainSuffix = ".trycloudflare.com"

    /// A connection code (as shown by the host) is `"<6-digit PIN>-<tunnel
    /// subdomain>"`, e.g. `123456-actual-words`. Splitting on the fixed
    /// 6-digit PIN prefix (rather than the first "-") is what makes this
    /// safe even though the tunnel subdomain itself contains hyphens.
    private static func parseConnectionCode(_ raw: String) -> (host: String, pin: String)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 7 else { return nil }
        let pin = String(trimmed.prefix(6))
        guard pin.allSatisfy(\.isNumber) else { return nil }
        let afterPinIndex = trimmed.index(trimmed.startIndex, offsetBy: 6)
        guard trimmed[afterPinIndex] == "-" else { return nil }
        var host = stripSchemeAndSlashes(String(trimmed[trimmed.index(after: afterPinIndex)...]))
        guard !host.isEmpty else { return nil }
        if !host.hasSuffix(tunnelDomainSuffix) {
            host += tunnelDomainSuffix
        }
        return (host, pin)
    }

    /// Lets the host part be a full URL (`https://xxxx.trycloudflare.com`) or
    /// just the bare hostname — both should work.
    private static func stripSchemeAndSlashes(_ raw: String) -> String {
        var address = raw.trimmingCharacters(in: .whitespaces)
        for prefix in ["https://", "wss://", "http://", "ws://"] where address.hasPrefix(prefix) {
            address.removeFirst(prefix.count)
        }
        return address.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
