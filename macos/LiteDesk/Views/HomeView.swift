import SwiftUI
import AppKit

/// The app's single persistent screen (design: "01 Ulanish") — hosting is
/// always live in the background (no explicit "start" step) and the connect
/// panel sits right next to it, matching the design's two-panel layout. Only
/// a successful outgoing connection replaces this with the full-screen
/// "02 Faol seans" view.
struct HomeView: View {
    @EnvironmentObject var loc: LocalizationManager
    @StateObject private var hostSession = HostSession()
    @StateObject private var viewerSession = ViewerSession()
    @State private var panelHeight: CGFloat?

    var body: some View {
        Group {
            if viewerSession.isConnected {
                ViewerRemoteView(session: viewerSession) {
                    viewerSession.disconnect()
                }
            } else {
                mainLayout
            }
        }
        .onAppear {
            hostSession.startIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hostSession.refreshPermissions()
        }
    }

    private var mainLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // zIndex above the panels below: without it, VStack paints
                // children in layout order, so the language dropdown's
                // overlay (which visually extends past the header's own
                // bounds) would be painted *under* the panels that follow
                // and their text would show through it.
                header
                    .zIndex(1)
                HStack(alignment: .top, spacing: 20) {
                    MyAddressPanel(session: hostSession, minHeight: panelHeight)
                        .equalHeight()
                    ConnectPanel(session: viewerSession, minHeight: panelHeight)
                        .equalHeight()
                }
                .onPreferenceChange(PanelHeightKey.self) { panelHeight = $0 }
            }
            .padding(28)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            logoMark
            Spacer()
            LanguagePicker()
        }
    }

    /// Replaces the old "LITEDESK" wordmark + tagline: the arrow-cursor logo
    /// on its navy square (DesignPalette.accent900, the design's darkest
    /// accent tone), matching the same mark used in the Windows client.
    private var logoMark: some View {
        ZStack {
            Rectangle().fill(DesignPalette.accent900)
            Image(systemName: "cursorarrow")
                .font(.system(size: 20, weight: .regular))
                .foregroundColor(.white)
        }
        .frame(width: 44, height: 44)
    }
}

/// Keeps the "Mening manzilim" / "Boshqa kompyuterga ulanish" cards the same
/// height as each other even though their content grows independently (e.g.
/// ping/FPS appearing under the address panel once a viewer connects).
private struct PanelHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension View {
    func equalHeight() -> some View {
        background(GeometryReader { geo in
            Color.clear.preference(key: PanelHeightKey.self, value: geo.size.height)
        })
    }
}

private struct LanguagePicker: View {
    @EnvironmentObject var loc: LocalizationManager

    @State private var isOpen = false

    // Plain Button + custom overlay list, not SwiftUI's `Menu` — on macOS
    // `Menu`'s AppKit-backed button chrome (`.menuStyle(.borderlessButton)`)
    // renders its label in a fixed system color and ignores an explicit
    // `.foregroundColor` on the label content, which made this control
    // invisible against the light background. This also matches the
    // mockup's own custom-drawn dropdown more closely than a native menu.
    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "globe")
                Text(loc.language.displayName)
                Image(systemName: "chevron.down").font(.system(size: 10))
            }
            .font(.system(size: 12.5, weight: .medium))
            .foregroundColor(Palette.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Palette.background)
            .overlay(Rectangle().strokeBorder(Palette.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if isOpen {
                dropdown
                    .offset(y: 38)
                    .zIndex(1)
            }
        }
    }

    private var dropdown: some View {
        VStack(spacing: 0) {
            ForEach(AppLanguage.allCases) { lang in
                let selected = lang == loc.language
                Button {
                    loc.language = lang
                    isOpen = false
                } label: {
                    HStack(spacing: 9) {
                        Circle()
                            .fill(selected ? Palette.accent : Color.clear)
                            .overlay(Circle().strokeBorder(Palette.border, lineWidth: selected ? 0 : 1))
                            .frame(width: 6, height: 6)
                        Text(lang.displayName)
                            .font(.system(size: 13.5))
                            .foregroundColor(Palette.text)
                        Spacer()
                        Text(lang.code)
                            .font(.system(size: 10.5))
                            .foregroundColor(Palette.subtitle)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(width: 190, alignment: .leading)
                    .background(selected ? DesignPalette.accent100 : Palette.background)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(Palette.background)
        .blueprintPanel()
        .shadow(color: Color.black.opacity(0.16), radius: 10, y: 4)
    }
}

/// Design panel "1" — the address others use to reach this computer. Folds
/// in the former HostRunningView's connected-state readout (ping/FPS) rather
/// than routing to a separate screen.
private struct MyAddressPanel: View {
    @ObservedObject var session: HostSession
    @EnvironmentObject var loc: LocalizationManager
    var minHeight: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                NumberBadge(number: 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc.t(.myAddressTitle)).heading(18)
                    Text(loc.t(.myAddressSubtitle))
                        .font(.system(size: 12))
                        .foregroundColor(Palette.subtitle)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(loc.t(.connectionAddressLabel)).eyebrow(11).foregroundColor(Palette.subtitle)
                addressBody
                HStack(spacing: 8) {
                    Button(loc.t(.copyButton)) { copyCode() }
                        .buttonStyle(.blueprintPrimary)
                        .disabled(session.connectionCode == nil)
                    Button(loc.t(.shareButton)) { shareCode() }
                        .buttonStyle(.blueprintSecondary)
                        .disabled(session.connectionCode == nil)
                    Spacer()
                    Button(loc.t(.newAddressButton)) { session.regenerate() }
                        .buttonStyle(.blueprintSecondary)
                }
            }
            .padding(14)
            .blueprintPanel()

            if session.viewerConnected {
                connectedStatus
            }

            if let error = session.errorMessage {
                Text(error).font(.system(size: 12)).foregroundColor(Palette.err)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: minHeight, alignment: .top)
        .blueprintPanel()
    }

    @ViewBuilder
    private var addressBody: some View {
        if let code = session.connectionCode {
            Text(code).heading(19).foregroundColor(Palette.accent).textSelection(.enabled)
        } else if case .failed(let message) = session.tunnelState {
            Text(message).font(.system(size: 12)).foregroundColor(Palette.err)
        } else {
            Text(loc.t(.tunnelStarting)).font(.system(size: 13)).foregroundColor(Palette.subtitle)
        }
    }

    private var connectedStatus: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Circle().fill(Palette.ok).frame(width: 8, height: 8)
                Text(loc.t(.connectedBadge)).font(.system(size: 12.5)).foregroundColor(Palette.ok)
            }
            if let ping = session.pingMs {
                Text("\(loc.t(.pingLabel)) \(Int(ping)) ms")
                    .font(.system(size: 12)).foregroundColor(Palette.subtitle)
            }
            Text("\(loc.t(.fpsLabel)) \(Int(session.outgoingFps))")
                .font(.system(size: 12)).foregroundColor(Palette.subtitle)
        }
    }

    private func copyCode() {
        guard let code = session.connectionCode else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(code, forType: .string)
    }

    private func shareCode() {
        guard let code = session.connectionCode else { return }
        let picker = NSSharingServicePicker(items: [code])
        if let view = NSApp.keyWindow?.contentView {
            picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
        }
    }
}

/// Design panel "2" — connect out to someone else's address.
private struct ConnectPanel: View {
    @ObservedObject var session: ViewerSession
    @EnvironmentObject var loc: LocalizationManager
    var minHeight: CGFloat?
    @State private var code: String = ""
    @State private var statusText: String = ""
    @State private var isConnecting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                NumberBadge(number: 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc.t(.connectTitle)).heading(18)
                    Text(loc.t(.connectSubtitle))
                        .font(.system(size: 12))
                        .foregroundColor(Palette.subtitle)
                }
            }

            FormField(label: loc.t(.connectionCodeLabel)) {
                TextField(loc.t(.connectionCodePlaceholder), text: $code)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, design: .monospaced))
                    .padding(10)
                    .background(DesignPalette.surface)
                    .blueprintPanel()
            }

            if !statusText.isEmpty {
                Text(statusText).font(.system(size: 12.5)).foregroundColor(Palette.err)
            }

            Button(isConnecting ? loc.t(.connectingButton) : loc.t(.connectButton)) { connect() }
                .buttonStyle(.blueprintPrimary)
                .disabled(isConnecting)

            Text(loc.t(.connectHint))
                .font(.system(size: 12))
                .foregroundColor(Palette.subtitle)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: minHeight, alignment: .top)
        .blueprintPanel()
    }

    private func connect() {
        guard let parsed = Self.parseConnectionCode(code) else {
            statusText = loc.t(.codeInvalidError)
            return
        }

        isConnecting = true
        statusText = ""
        session.connect(host: parsed.host, password: parsed.pin) { success, error in
            isConnecting = false
            if !success {
                statusText = loc.t(.connectErrorPrefix) + (error ?? "")
            }
        }
    }

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
        if !host.hasSuffix(HostSession.tunnelDomainSuffix) {
            host += HostSession.tunnelDomainSuffix
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

