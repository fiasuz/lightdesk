import SwiftUI

struct RootView: View {
    var body: some View {
        HomeView()
            .frame(minWidth: 760, minHeight: 560)
            .background(Palette.background)
            .foregroundColor(Palette.text)
    }
}

/// Kept as the app-wide color alias so every screen picks up the design
/// system's palette (see DesignSystem.swift) without touching each call site.
enum Palette {
    static let background = DesignPalette.background
    static let card = DesignPalette.surface
    static let border = DesignPalette.divider
    static let text = DesignPalette.text
    static let subtitle = DesignPalette.textMuted55
    static let accent = DesignPalette.accent
    static let ok = DesignPalette.ok
    static let err = DesignPalette.err
}

struct FormField<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .eyebrow(11)
                .foregroundColor(Palette.subtitle)
            content
        }
    }
}
