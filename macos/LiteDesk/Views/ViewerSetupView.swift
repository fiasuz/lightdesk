import SwiftUI

struct ViewerSetupView: View {
    @ObservedObject var session: ViewerSession
    @State private var password: String = ""
    @State private var statusText: String = ""
    @State private var isConnecting = false

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 4) {
                Text("Boshqa kompyuterga ulanish").font(.system(size: 22, weight: .semibold))
                Text("Boshqa kompyuterda ko'rsatilgan ulanish kodini kiriting")
                    .font(.system(size: 13))
                    .foregroundColor(Palette.subtitle)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 14) {
                FormField(label: "Ulanish kodi") {
                    TextField("masalan: 123456-xxxx", text: $password)
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
        guard let parsed = Self.parseConnectionCode(password) else {
            statusText = "Kodni tekshiring — to'liq ulanish kodini kiriting"
            return
        }

        isConnecting = true
        statusText = ""
        session.connect(host: parsed.host, password: parsed.pin) { success, error in
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
