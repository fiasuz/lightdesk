import SwiftUI
import AppKit

/// Design screen "02 Faol seans" — header with live ping/FPS/duration, the
/// remote surface, and a "Kuzatuv" (monitoring) sidebar with real sparklines.
struct ViewerRemoteView: View {
    @ObservedObject var session: ViewerSession
    @EnvironmentObject var loc: LocalizationManager
    let onDisconnect: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                RemoteSurfaceRepresentable(session: session)
                    .background(Color.black)
            }
            monitoringSidebar
        }
    }

    private var header: some View {
        HStack(spacing: 20) {
            HStack(spacing: 8) {
                Circle().fill(Palette.ok).frame(width: 8, height: 8)
                Text(session.connectedHost.isEmpty ? loc.t(.connectedBadge) : session.connectedHost)
                    .heading(15)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 18) {
                statPair(loc.t(.pingLabel), session.pingMs.map { String(format: "%.0f ms", $0) } ?? "—")
                statPair(loc.t(.fpsLabel), String(format: "%.0f", session.incomingFps))
                TimelineView(.periodic(from: session.connectedAt ?? Date(), by: 1)) { context in
                    statPair(loc.t(.timeLabel), Self.elapsed(since: session.connectedAt, now: context.date))
                }
            }
            .font(.system(size: 12))
            .foregroundColor(Palette.subtitle)

            Button(loc.t(.sessionEndButton), action: onDisconnect)
                .buttonStyle(.blueprintSecondary)
        }
        .padding(.horizontal, 18)
        .frame(height: 48)
        .background(Palette.card)
        .overlay(Rectangle().fill(Palette.border).frame(height: 1), alignment: .bottom)
    }

    private func statPair(_ label: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Text(label)
            Text(value).foregroundColor(Palette.text).fontWeight(.semibold)
        }
    }

    private static func elapsed(since start: Date?, now: Date) -> String {
        guard let start else { return "00:00:00" }
        let total = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    private var monitoringSidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(loc.t(.monitoringTitle)).eyebrow(11).foregroundColor(Palette.accent)

            metricGraph(
                title: loc.t(.pingLabel),
                value: session.pingMs.map { String(format: "%.0f ms", $0) } ?? "—",
                history: session.pingHistory,
                color: DesignPalette.accent
            )
            metricGraph(
                title: loc.t(.fpsLabel),
                value: String(format: "%.0f", session.incomingFps),
                history: session.fpsHistory,
                color: DesignPalette.accent400
            )

            Rectangle().fill(Palette.border).frame(height: 1)

            statRow(loc.t(.fpsLabel), String(format: "%.0f", session.incomingFps))
            statRow(loc.t(.trafficLabel), String(format: "%.2f Mb/s", session.incomingKbps / 1000))

            Spacer()
        }
        .padding(16)
        .frame(width: 260)
        .background(Palette.card)
        .overlay(Rectangle().fill(Palette.border).frame(width: 1), alignment: .leading)
    }

    private func metricGraph(title: String, value: String, history: [Double], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 12)).foregroundColor(Palette.subtitle)
                Spacer()
                Text(value).heading(15)
            }
            SparklineView(values: history, color: color)
                .frame(height: 44)
        }
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 12)).foregroundColor(Palette.subtitle)
            Spacer()
            Text(value).font(.system(size: 12, weight: .semibold))
        }
    }
}

/// Simple normalized line chart over the last ~60 one-second samples.
private struct SparklineView: View {
    let values: [Double]
    var color: Color = DesignPalette.accent

    var body: some View {
        GeometryReader { geo in
            Path { path in
                guard values.count > 1 else { return }
                let maxV = max(values.max() ?? 1, 1)
                let minV = min(values.min() ?? 0, maxV - 1)
                let range = max(maxV - minV, 1)
                let stepX = geo.size.width / CGFloat(values.count - 1)
                for (index, value) in values.enumerated() {
                    let x = CGFloat(index) * stepX
                    let normalized = (value - minV) / range
                    let y = geo.size.height * (1 - CGFloat(normalized))
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(color, lineWidth: 1.5)
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

        func remoteSurfaceViewDidPressKey(code: String) {
            session.sendKeyDown(code: code)
        }

        func remoteSurfaceViewDidReleaseKey(code: String) {
            session.sendKeyUp(code: code)
        }
    }
}
