import SwiftUI

struct HostContainerView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var session = HostSession()

    var body: some View {
        VStack(spacing: 0) {
            BackLink { appState.mode = .home }
            if session.isRunning {
                HostRunningView(session: session)
            } else {
                HostSetupView(session: session)
            }
        }
    }
}
