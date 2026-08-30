import SwiftUI

struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            switch appState.mode {
            case .home:
                HomeView()
            case .host:
                HostContainerView()
            case .viewer:
                ViewerContainerView()
            }
        }
        .frame(minWidth: 480, minHeight: 420)
        .background(Palette.background)
        .foregroundColor(Palette.text)
    }
}

enum Palette {
    static let background = Color(red: 0x14 / 255.0, green: 0x17 / 255.0, blue: 0x1c / 255.0)
    static let card = Color(red: 0x1e / 255.0, green: 0x22 / 255.0, blue: 0x29 / 255.0)
    static let border = Color(red: 0x2b / 255.0, green: 0x30 / 255.0, blue: 0x3a / 255.0)
    static let text = Color(red: 0xe8 / 255.0, green: 0xea / 255.0, blue: 0xed / 255.0)
    static let subtitle = Color(red: 0x9a / 255.0, green: 0xa0 / 255.0, blue: 0xa6 / 255.0)
    static let accent = Color(red: 0x4c / 255.0, green: 0x8b / 255.0, blue: 0xf5 / 255.0)
    static let ok = Color(red: 0x6b / 255.0, green: 0xcf / 255.0, blue: 0x7f / 255.0)
    static let err = Color(red: 0xf2 / 255.0, green: 0x8b / 255.0, blue: 0x82 / 255.0)
}

struct BackLink: View {
    let action: () -> Void

    var body: some View {
        HStack {
            Button(action: action) {
                Text("← Orqaga").font(.system(size: 13)).foregroundColor(Palette.subtitle)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding([.top, .leading], 16)
    }
}

struct FormField<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 12)).foregroundColor(Palette.subtitle)
            content
        }
    }
}
