import AppKit
import SwiftUI

@main
struct LiteDeskMain {
    static func main() {
        let delegate = AppDelegate()
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private let localization = LocalizationManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let root = RootView().environmentObject(localization).preferredColorScheme(.light)
        let hosting = NSHostingView(rootView: root)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "LiteDesk"
        window.contentView = hosting
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Belt-and-suspenders: Process doesn't auto-kill children when this
        // app exits, so make sure no cloudflared tunnel is left running.
        CloudflaredTunnelManager.stopAll()
    }
}
