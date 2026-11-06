import SwiftUI

/// Every color, size and surface the UI uses. Matches Panefold: soft cards on the
/// window background, system fonts, accent color for selection and primary actions.
enum Theme {
    static let radius: CGFloat = 12
    static let tileRadius: CGFloat = 6
    static let padding: CGFloat = 14
    static let gap: CGFloat = 14
    static let pagePadding: CGFloat = 20

    /// Big numbers: the stats row and the sizes drawn in treemap tiles.
    static func number(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

extension Color {
    static let page = Color(nsColor: .windowBackgroundColor)
    /// The soft card fill, drawn over the window background.
    static let cardFill = Color.primary.opacity(0.04)
    static let rowHover = Color.primary.opacity(0.05)
}

private struct CardStyle: ViewModifier {
    var padding: CGFloat?

    func body(content: Content) -> some View {
        content
            .padding(padding ?? 0)
            .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Color.cardFill))
    }
}

extension View {
    /// Panefold's grouped card: a soft fill, no border, no shadow.
    func card(padding: CGFloat? = nil) -> some View { modifier(CardStyle(padding: padding)) }

    /// An opaque card-colored background, for headers pinned over scrolling card content.
    func cardSurface() -> some View { background(Color.cardFill).background(Color.page) }

    /// A small tinted capsule, like Panefold's tile badges.
    func badge(_ tint: Color) -> some View {
        font(.caption2.bold())
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

extension FileCategory {
    var color: Color {
        switch self {
        case .media: Color(red: 0.95, green: 0.50, blue: 0.20)
        case .dev: Color(red: 0.55, green: 0.56, blue: 0.60)
        case .code: Color(red: 0.47, green: 0.40, blue: 0.93)
        case .sdk: Color(red: 0.15, green: 0.65, blue: 0.75)
        case .ai: Color(red: 0.88, green: 0.33, blue: 0.58)
        case .caches: Color(red: 0.28, green: 0.47, blue: 0.93)
        case .system: Color(red: 0.36, green: 0.42, blue: 0.50)
        }
    }
}

extension Safety {
    var color: Color {
        switch self {
        case .safe: .green
        case .review: .orange
        }
    }
}
