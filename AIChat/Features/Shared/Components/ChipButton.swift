import SwiftUI

/// Чип: подсказки в пустом чате (контур) и категории шаблонов (выбранный — градиент).
struct ChipButton: View {
    enum Style {
        /// Тёмная подложка с тонкой обводкой; выбранный — градиентная обводка.
        case outline
        /// Выбранный залит градиентом, остальные — тёмная подложка.
        case filled
        /// Подсказка в пустом чате: `card` 80%, обводка 12% белого, Inter 14.
        case suggestion
    }

    let title: String
    var isSelected = false
    var style = Style.outline
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // Текст чипа — данные (категория из API) или уже локализованная подсказка.
            Text(verbatimTitle)
                .font(style == .suggestion ? AppFont.subheadline : AppFont.caption)
                .foregroundStyle(Color.appAccent.opacity(style == .suggestion ? 0.9 : 1))
                .lineLimit(1)
                .padding(.horizontal, style == .suggestion ? 14 : 12)
                .padding(.vertical, style == .suggestion ? 10 : 8)
                .background(background)
                .overlay(border)
                .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var verbatimTitle: String { title }

    @ViewBuilder
    private var background: some View {
        if style == .filled, isSelected {
            Capsule().fill(AppGradient.primary)
        } else if style == .suggestion {
            Capsule().fill(Color.appSurface.opacity(0.8))
        } else {
            Capsule().fill(Color.appFillTertiary)
        }
    }

    @ViewBuilder
    private var border: some View {
        if style == .outline, isSelected {
            Capsule().strokeBorder(AppGradient.primary, lineWidth: 1)
        } else if style == .suggestion {
            Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        } else if !(style == .filled && isSelected) {
            Capsule().strokeBorder(Color.appSeparator, lineWidth: 1)
        }
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 12) {
        HStack { ChipButton(title: "Explain simply") {}; ChipButton(title: "Plan my day") {} }
        HStack {
            ChipButton(title: "Clay") {}
            ChipButton(title: "Cartoon", isSelected: true) {}
        }
        HStack {
            ChipButton(title: "Popular", isSelected: true, style: .filled) {}
            ChipButton(title: "Funny", style: .filled) {}
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.appBackground)
}
#endif
