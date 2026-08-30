import SwiftUI
import AppKit

struct ViewerRemoteView: View {
    @ObservedObject var session: ViewerSession
    let onDisconnect: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Circle().fill(Palette.ok).frame(width: 8, height: 8)
                Text("Ulandi")
                    .font(.system(size: 13))
                    .foregroundColor(Palette.subtitle)
                Spacer()
                Button("Uzish", action: onDisconnect)
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(Palette.background.opacity(0.85))

            RemoteSurfaceRepresentable(session: session)
                .background(Color.black)
        }
    }
}

/// Bridges the AppKit RemoteSurfaceView (frame rendering + raw mouse capture)
/// into SwiftUI. Frames and mouse events flow through direct closures/delegate
/// calls, not @Published, to avoid SwiftUI re-render overhead at ~8fps.
struct RemoteSurfaceRepresentable: NSViewRepresentable {
    @ObservedObject var session: ViewerSession

    func makeNSView(context: Context) -> RemoteSurfaceView {
        let view = RemoteSurfaceView()
        view.delegate = context.coordinator
        session.onFrame = { [weak view] data in
            DispatchQueue.main.async {
                view?.present(frameData: data)
            }
        }
        return view
    }

    func updateNSView(_ nsView: RemoteSurfaceView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    final class Coordinator: RemoteSurfaceViewDelegate {
        private let session: ViewerSession

        init(session: ViewerSession) {
            self.session = session
        }

        func remoteSurfaceViewDidMoveMouse(x: Double, y: Double) {
            session.sendMouseMove(x: x, y: y)
        }

        func remoteSurfaceViewDidPressMouse(x: Double, y: Double, button: String) {
            session.sendMouseDown(x: x, y: y, button: button)
        }

        func remoteSurfaceViewDidReleaseMouse(button: String) {
            session.sendMouseUp(button: button)
        }

        func remoteSurfaceViewDidScroll(dx: Double, dy: Double) {
            session.sendMouseScroll(dx: dx, dy: dy)
        }
    }
}
