import SwiftUI

/// Поле ввода внизу чата: карточка `card` со скруглёнными верхними углами, текст растёт
/// до 3 строк (дальше — прокрутка внутри поля), справа — круглая градиентная кнопка отправки.
struct MessageInputBar: View {
    @Binding var text: String
    let placeholder: LocalizedStringKey
    var isSendEnabled: Bool
    var focus: FocusState<Bool>.Binding
    let onSend: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField(placeholder, text: $text, axis: .vertical)
                .font(AppFont.body)
                .foregroundStyle(Color.appAccent)
                .tint(.appGradientEnd)
                .lineLimit(1...3)
                .focused(focus)
                .padding(.vertical, 10)
            SendButton(isEnabled: isSendEnabled, action: onSend)
        }
        .padding(.horizontal, AppMetrics.sideInset)
        .padding(.vertical, 14)
        .background(
            UnevenTopRoundedRectangle(radius: AppMetrics.cardRadius)
                .fill(Color.appSurface)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

/// Круглая кнопка отправки 40pt с градиентом; неактивная — 30% прозрачности.
struct SendButton: View {
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image("IconSend")
                .renderingMode(.template)
                .foregroundStyle(Color.appAccent)
                .frame(width: 40, height: 40)
                .background(AppGradient.primary, in: Circle())
                .opacity(isEnabled ? 1 : 0.3)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!isEnabled)
        .accessibilityLabel(Text("Send"))
        .animation(.easeInOut(duration: 0.2), value: isEnabled)
    }
}

/// Прямоугольник со скруглёнными только верхними углами (`UnevenRoundedRectangle` — с iOS 17).
struct UnevenTopRoundedRectangle: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: rect, byRoundingCorners: [.topLeft, .topRight],
                          cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}

#if DEBUG
private struct MessageInputBarPreview: View {
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack {
            Spacer()
            MessageInputBar(text: $text, placeholder: "How can I help you?",
                            isSendEnabled: !text.isEmpty, focus: $focused) {}
        }
        .background(Color.appBackground)
    }
}

#Preview { MessageInputBarPreview() }
#endif
