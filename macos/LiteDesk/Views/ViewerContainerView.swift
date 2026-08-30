import SwiftUI

struct ViewerContainerView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var session = ViewerSession()

    var body: some View {
        VStack(spacing: 0) {
            if session.isConnected {
                ViewerRemoteView(session: session) {
                    session.disconnect()
                }
            } else {
                BackLink { appState.mode = .home }
                ViewerSetupView(session: session)
            }
        }
    }
}
