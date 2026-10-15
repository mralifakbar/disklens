import SwiftUI

import SwiftUI

extension Color {
    static let page = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let hairline = Color.primary.opacity(0.1)
}

private struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.hairline))
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
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
        case .safe: Color(red: 0.20, green: 0.64, blue: 0.33)
        case .review: Color(red: 0.93, green: 0.55, blue: 0.13)
        }
    }
}
