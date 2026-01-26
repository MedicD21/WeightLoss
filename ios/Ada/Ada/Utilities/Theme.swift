import SwiftUI

/// Ada's dark minimalist design system
enum Theme {
    // MARK: - Colors

    enum Colors {
        // Background colors
        static let background = Color(hex: "0A0A0A")
        static let surface = Color(hex: "141414")
        static let surfaceElevated = Color(hex: "1C1C1C")
        static let surfaceHighlight = Color(hex: "252525")

        // Text colors
        static let textPrimary = Color(hex: "FAFAFA")
        static let textSecondary = Color(hex: "A0A0A0")
        static let textTertiary = Color(hex: "666666")

        // Accent colors
        static let accent = Color(hex: "6366F1") // Indigo
        static let accentLight = Color(hex: "818CF8")
        static let accentDark = Color(hex: "4F46E5")

        // Semantic colors
        static let success = Color(hex: "22C55E")
        static let warning = Color(hex: "F59E0B")
        static let error = Color(hex: "EF4444")
        static let info = Color(hex: "3B82F6")

        // Macro colors
        static let protein = Color(hex: "EF4444") // Red
        static let carbs = Color(hex: "F59E0B") // Amber
        static let fat = Color(hex: "8B5CF6") // Purple
        static let calories = Color(hex: "22C55E") // Green

        // Chart colors
        static let chartLine = accent
        static let chartFill = accent.opacity(0.2)
        static let chartGrid = Color(hex: "333333")

        // Border/Divider
        static let border = Color(hex: "2A2A2A")
        static let divider = Color(hex: "1F1F1F")
    }

    // MARK: - Typography

    enum Typography {
        // Headlines
        static let largeTitle = Font.system(size: 34, weight: .bold, design: .rounded)
        static let title1 = Font.system(size: 28, weight: .bold, design: .rounded)
        static let title2 = Font.system(size: 22, weight: .semibold, design: .rounded)
        static let title3 = Font.system(size: 20, weight: .semibold, design: .rounded)

        // Body
        static let headline = Font.system(size: 17, weight: .semibold, design: .default)
        static let body = Font.system(size: 17, weight: .regular, design: .default)
        static let callout = Font.system(size: 16, weight: .regular, design: .default)
        static let subheadline = Font.system(size: 15, weight: .regular, design: .default)
        static let footnote = Font.system(size: 13, weight: .regular, design: .default)
        static let caption = Font.system(size: 12, weight: .regular, design: .default)
        static let caption2 = Font.system(size: 11, weight: .regular, design: .default)

        // Numbers
        static let statLarge = Font.system(size: 48, weight: .bold, design: .rounded)
        static let statMedium = Font.system(size: 32, weight: .bold, design: .rounded)
        static let statSmall = Font.system(size: 24, weight: .semibold, design: .rounded)
    }

    // MARK: - Spacing

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: - Corner Radius

    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let xl: CGFloat = 24
        static let full: CGFloat = 9999
    }

    // MARK: - Shadows

    enum Shadows {
        static let small = Color.black.opacity(0.15)
        static let medium = Color.black.opacity(0.25)
        static let large = Color.black.opacity(0.35)
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - View Modifiers

struct CardStyle: ViewModifier {
    var elevated: Bool = false

    func body(content: Content) -> some View {
        content
            .background(elevated ? Theme.Colors.surfaceElevated : Theme.Colors.surface)
            .cornerRadius(Theme.Radius.medium)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md)
            .background(isEnabled ? Theme.Colors.accent : Theme.Colors.textTertiary)
            .cornerRadius(Theme.Radius.medium)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.headline)
            .foregroundColor(Theme.Colors.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md)
            .background(Theme.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.medium)
                    .stroke(Theme.Colors.accent, lineWidth: 1)
            )
            .cornerRadius(Theme.Radius.medium)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

extension View {
    func cardStyle(elevated: Bool = false) -> some View {
        modifier(CardStyle(elevated: elevated))
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}
