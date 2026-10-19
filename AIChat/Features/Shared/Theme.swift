import SwiftUI

// Дизайн-основа: цвета только из Assets.xcassets и системные; шрифты системные
// с Dynamic Type. Токены из Figma появятся в шаге 5.1 плана.

extension ShapeStyle where Self == Color {
    /// Фон экранов.
    static var appBackground: Color { Color("Background") }
    /// Карточки, поле ввода, пузыри.
    static var appSurface: Color { Color("Surface") }
    /// Акцент.
    static var appAccent: Color { Color("Accent") }
}

/// Стили текста.
enum TextStyle {
    case assistantMessage
    case userMessage
    case chatTitle
    case caption

    var font: Font {
        switch self {
        case .assistantMessage, .userMessage: .body
        case .chatTitle: .headline
        case .caption: .caption
        }
    }
}

extension View {
    func textStyle(_ style: TextStyle) -> some View {
        font(style.font)
    }
}

#if DEBUG
private struct ThemeSwatches: View {
    var body: some View {
        HStack(spacing: 12) {
            swatch(.appBackground)
            swatch(.appSurface)
            swatch(.appAccent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }

    private func swatch(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(color)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.secondary.opacity(0.3)))
            .frame(width: 64, height: 64)
    }
}

#Preview { ThemeSwatches() }
#endif
