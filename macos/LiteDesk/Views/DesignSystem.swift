import SwiftUI

/// "Blueprint" visual language shared by every screen: square corners, hairline
/// dividers, small cross-shaped registration marks at panel corners, an accent
/// ramp, and a condensed-style heading font (approximated — no bundled font).
/// Source: the LiteDesk.dc.html design canvas ("Remote desktop application design").

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

enum DesignPalette {
    static let background = Color(hex: 0xF2F2F3)
    static let surface = Color(hex: 0xE9E9EA)
    static let text = Color(hex: 0x1D1F20)
    static let divider = Color.black.opacity(0.16)

    static let accent100 = Color(hex: 0xEEF6FF)
    static let accent300 = Color(hex: 0xB5D9FD)
    static let accent400 = Color(hex: 0x94BCE3)
    static let accent600 = Color(hex: 0x597EA3)
    static let accent700 = Color(hex: 0x416180)
    static let accent800 = Color(hex: 0x2C455D)
    static let accent900 = Color(hex: 0x1D2D3D)
    static let accent = Color(hex: 0x5980A6)

    static let textMuted45 = text.opacity(0.45)
    static let textMuted55 = text.opacity(0.55)
    static let textMuted60 = text.opacity(0.60)

    static let ok = Color(hex: 0x3F8F5C)
    static let err = Color(hex: 0xB23B3B)
}

// MARK: - Typography

extension Text {
    /// Approximates the design's condensed heading face (Barlow Condensed) with
    /// the system font's semibold weight plus tight tracking — no bundled font.
    func heading(_ size: CGFloat, tracking amount: CGFloat = 0) -> Text {
        self.font(.system(size: size, weight: .semibold)).tracking(amount)
    }

    func eyebrow(_ size: CGFloat = 12) -> Text {
        self.font(.system(size: size, weight: .medium)).tracking(size * 0.09)
    }
}

// MARK: - Blueprint panel (hairline border + corner registration marks)

private struct CornerMark: View {
    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 5, y: 0))
            path.addLine(to: CGPoint(x: 5, y: 11))
            path.move(to: CGPoint(x: 0, y: 5))
            path.addLine(to: CGPoint(x: 11, y: 5))
        }
        .stroke(DesignPalette.textMuted55, lineWidth: 1)
        .frame(width: 11, height: 11)
    }
}

private struct BlueprintPanel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlay(Rectangle().strokeBorder(DesignPalette.divider, lineWidth: 1))
            .overlay(alignment: .topLeading) { CornerMark().offset(x: -6, y: -6) }
            .overlay(alignment: .topTrailing) { CornerMark().offset(x: 6, y: -6) }
            .overlay(alignment: .bottomLeading) { CornerMark().offset(x: -6, y: 6) }
            .overlay(alignment: .bottomTrailing) { CornerMark().offset(x: 6, y: 6) }
    }
}

extension View {
    /// Square hairline border with the design system's corner registration marks.
    func blueprintPanel() -> some View {
        modifier(BlueprintPanel())
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .tracking(0.4)
            .foregroundColor(DesignPalette.background)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(configuration.isPressed ? DesignPalette.accent700 : DesignPalette.accent)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(DesignPalette.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(configuration.isPressed ? DesignPalette.text.opacity(0.14) : Color.clear)
            .overlay(Rectangle().strokeBorder(DesignPalette.divider, lineWidth: 1))
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var blueprintPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var blueprintSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

// MARK: - Tags

enum TagStyle {
    case accent
    case outline
}

struct TagView: View {
    let text: String
    var style: TagStyle = .accent

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(style == .accent ? DesignPalette.accent100 : Color.clear)
            .foregroundColor(style == .accent ? DesignPalette.accent800 : DesignPalette.accent)
            .overlay(
                Rectangle().strokeBorder(style == .outline ? DesignPalette.accent : Color.clear, lineWidth: 1)
            )
    }
}

// MARK: - Numbered badge (the small square "1"/"2"/"3" markers in the design)

struct NumberBadge: View {
    let number: Int

    var body: some View {
        Text("\(number)")
            .heading(15)
            .foregroundColor(DesignPalette.background)
            .frame(width: 26, height: 26)
            .background(DesignPalette.accent)
    }
}

// MARK: - Two-way platform segment (mirrors the design's macOS / Windows toggle)

struct TwoOptionSegment: View {
    let leftLabel: String
    let rightLabel: String
    @Binding var isRight: Bool

    var body: some View {
        HStack(spacing: 0) {
            option(leftLabel, selected: !isRight) { isRight = false }
            Rectangle().fill(DesignPalette.divider).frame(width: 1)
            option(rightLabel, selected: isRight) { isRight = true }
        }
        .overlay(Rectangle().strokeBorder(DesignPalette.divider, lineWidth: 1))
    }

    private func option(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .heading(13)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .foregroundColor(selected ? DesignPalette.background : DesignPalette.text)
                .background(selected ? DesignPalette.accent : Color.clear)
        }
        .buttonStyle(.plain)
    }
}
