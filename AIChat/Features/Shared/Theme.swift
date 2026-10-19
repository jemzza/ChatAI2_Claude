import SwiftUI

// Дизайн-токены из Figma (docs/task.md, «Цвета/шрифты»). Во View — только они:
// цвета из Assets.xcassets, шрифт Inter через `AppFont`, размеры через `AppMetrics`.

extension ShapeStyle where Self == Color {
    /// `background` — фон экранов, #0B070E.
    static var appBackground: Color { Color("Background") }
    /// `card` — карточки, поле ввода, ответ ассистента, #1F191F.
    static var appSurface: Color { Color("Surface") }
    /// `accent` / `text` — основной текст и иконки.
    static var appAccent: Color { Color("Accent") }
    /// `text 2` — второстепенный текст, плейсхолдеры, #606060.
    static var appTextSecondary: Color { Color("TextSecondary") }
    /// `label/tertiary` — подписи на тёмном (60% белого).
    static var appLabelTertiary: Color { .white.opacity(0.6) }
    /// Обводка невыбранных карточек и чипов (30% белого).
    static var appStroke: Color { .white.opacity(0.3) }
    /// `background/tertiary` — подложка сегментов и строк (8% белого).
    static var appFillTertiary: Color { .white.opacity(0.08) }
    /// `separator/secondary` — обводка тостов (16% белого).
    static var appSeparator: Color { .white.opacity(0.16) }
    /// `background/quaternary` (14% белого).
    static var appFillQuaternary: Color { .white.opacity(0.14) }
    static var appGradientStart: Color { Color("GradientStart") }
    static var appGradientEnd: Color { Color("GradientEnd") }
}

enum AppGradient {
    /// Фирменный градиент кнопок, бейджей и пузыря пользователя: #98C6F7 → #EB5B92.
    static let primary = LinearGradient(colors: [.appGradientStart, .appGradientEnd],
                                        startPoint: .leading, endPoint: .trailing)
}

/// Шрифты макета. Inter масштабируется вместе с Dynamic Type (`relativeTo:`).
enum AppFont {
    /// «Create anything you want» — Inter Bold 34.
    static let largeTitle = inter("Inter-Bold", 34, relativeTo: .largeTitle)
    /// «Your AI tools, ready to go» — Inter Bold 28.
    static let title = inter("Inter-Bold", 28, relativeTo: .title)
    /// Заголовки пустых состояний и секций — Inter SemiBold 20.
    static let title3 = inter("Inter-SemiBold", 20, relativeTo: .title3)
    static let title3Medium = inter("Inter-Medium", 20, relativeTo: .title3)
    /// Заголовок навбара — Inter SemiBold 18.
    static let navigationTitle = inter("Inter-SemiBold", 18, relativeTo: .headline)
    /// Кнопки, заголовки секций — Inter SemiBold 16.
    static let headline = inter("Inter-SemiBold", 16, relativeTo: .headline)
    static let bodyMedium = inter("Inter-Medium", 16, relativeTo: .body)
    static let body = inter("Inter-Regular", 16, relativeTo: .body)
    /// Сообщения чата, подписи карточек — Inter 14.
    static let subheadlineMedium = inter("Inter-Medium", 14, relativeTo: .subheadline)
    static let subheadline = inter("Inter-Regular", 14, relativeTo: .subheadline)
    /// Чипы, мелкие подписи — Inter 12.
    static let caption = inter("Inter-Regular", 12, relativeTo: .caption)
    static let captionMedium = inter("Inter-Medium", 12, relativeTo: .caption)
    /// Где в макете SF Pro (юридические ссылки, «Cancel Anytime») — системный шрифт.
    static let systemCaption = Font.system(size: 12)
    static let systemCaption2 = Font.system(size: 11)

    private static func inter(_ name: String, _ size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        .custom(name, size: size, relativeTo: style)
    }
}

/// Размеры из макета.
enum AppMetrics {
    /// `safeAreaSideInset` — боковые отступы экранов.
    static let sideInset: CGFloat = 16
    /// `spacing/cellSpacing`.
    static let cellSpacing: CGFloat = 8
    /// `spacing/verticalSectionSpacing`.
    static let sectionSpacing: CGFloat = 28
    /// Карточки тарифов, большие кнопки, поле ввода.
    static let cardRadius: CGFloat = 24
    /// Строки списков и настроек.
    static let rowRadius: CGFloat = 16
    /// Высота строки настроек и истории.
    static let rowHeight: CGFloat = 44
    /// Чипы и бейджи — капсула.
    static let chipRadius: CGFloat = 32
    /// Высота основной кнопки.
    static let buttonHeight: CGFloat = 50
}

/// Стили текста сообщений чата (использует `MarkdownView`).
enum TextStyle {
    case assistantMessage
    case userMessage
    case chatTitle
    case caption

    var font: Font {
        switch self {
        case .assistantMessage, .userMessage: AppFont.subheadline
        case .chatTitle: AppFont.headline
        case .caption: AppFont.caption
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    swatch(.appBackground)
                    swatch(.appSurface)
                    swatch(.appTextSecondary)
                    swatch(.appGradientStart)
                    swatch(.appGradientEnd)
                }
                Capsule().fill(AppGradient.primary).frame(height: AppMetrics.buttonHeight)
                // Образцы шрифтов — тексты из макета.
                Text("Create anything you want").font(AppFont.largeTitle)
                Text("Your AI tools, ready to go").font(AppFont.title)
                Text("Unlock now").font(AppFont.headline)
                Text("Get results in seconds").font(AppFont.bodyMedium)
                Text("Pick a suggestion below or ask your own question").font(AppFont.caption)
                    .foregroundStyle(Color.appTextSecondary)
            }
            .foregroundStyle(Color.appAccent)
            .padding(AppMetrics.sideInset)
        }
        .background(Color.appBackground)
    }

    private func swatch(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(color)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.appStroke))
            .frame(width: 48, height: 48)
    }
}

#Preview { ThemeSwatches() }
#endif
