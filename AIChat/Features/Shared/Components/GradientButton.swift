import SwiftUI

/// Основная кнопка макета: градиент, Inter SemiBold 16, высота 50, радиус 24.
/// Неактивная — полупрозрачная; во время загрузки — индикатор вместо текста.
struct GradientButton: View {
    let title: LocalizedStringKey
    var isEnabled = true
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .font(AppFont.headline)
                    .opacity(isLoading ? 0 : 1)
                if isLoading {
                    ProgressView().tint(.appAccent)
                }
            }
            .foregroundStyle(Color.appAccent)
            .frame(maxWidth: .infinity)
            .frame(height: AppMetrics.buttonHeight)
            .background(AppGradient.primary, in: RoundedRectangle(cornerRadius: AppMetrics.cardRadius))
            .opacity(isEnabled ? 1 : 0.3)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!isEnabled || isLoading)
        .animation(.easeInOut(duration: 0.2), value: isEnabled)
        .animation(.easeInOut(duration: 0.2), value: isLoading)
    }
}

/// Лёгкое «нажатие» без системной подсветки: масштаб и прозрачность.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 16) {
        GradientButton(title: "Unlock now") {}
        GradientButton(title: "Create", isEnabled: false) {}
        GradientButton(title: "Continue", isLoading: true) {}
    }
    .padding(AppMetrics.sideInset)
    .frame(maxHeight: .infinity)
    .background(Color.appBackground)
}
#endif
