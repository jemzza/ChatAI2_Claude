import SwiftUI

/// Уведомление сверху экрана из макета: «Copied», «Copy failed», «Upload failed».
struct ToastMessage: Equatable, Identifiable {
    enum Kind: Equatable {
        case success
        case failure
    }

    let id = UUID()
    let kind: Kind
    let text: LocalizedStringKey

    static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool { lhs.id == rhs.id }
}

struct ToastView: View {
    let message: ToastMessage

    var body: some View {
        HStack(spacing: 12) {
            icon
                .frame(width: 24, height: 24)
            Text(message.text)
                .font(AppFont.headline)
                .foregroundStyle(Color.appAccent)
                .padding(.trailing, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        // В макете — `card` 40% + сильный блюр фона; на тёмном фоне это почти сплошной `card`.
        .background(Color.appSurface.opacity(0.9), in: RoundedRectangle(cornerRadius: AppMetrics.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: AppMetrics.cardRadius).strokeBorder(Color.appSeparator))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var icon: some View {
        switch message.kind {
        case .success:
            Image("IconCheck")
        case .failure:
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.red)
        }
    }
}

extension View {
    /// Показывает тост сверху на 2 с; свайп вверх закрывает раньше (заметки к макету).
    func toast(_ message: Binding<ToastMessage?>, duration: Duration = .seconds(2)) -> some View {
        modifier(ToastModifier(message: message, duration: duration))
    }
}

private struct ToastModifier: ViewModifier {
    @Binding var message: ToastMessage?
    let duration: Duration
    @State private var dragOffset: CGFloat = 0

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let current = message {
                ToastView(message: current)
                    .offset(y: min(dragOffset, 0))
                    .gesture(
                        DragGesture()
                            .onChanged { dragOffset = $0.translation.height }
                            .onEnded { value in
                                if value.translation.height < -20 { dismiss(current) }
                                withAnimation(.spring()) { dragOffset = 0 }
                            }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: current.id) {
                        try? await Task.sleep(for: duration)
                        dismiss(current)
                    }
                    .padding(.top, 4)
                    .zIndex(1)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: message)
    }

    private func dismiss(_ shown: ToastMessage) {
        guard message?.id == shown.id else { return }
        message = nil
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 16) {
        ToastView(message: ToastMessage(kind: .success, text: "Copied"))
        ToastView(message: ToastMessage(kind: .failure, text: "Copy failed"))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.appBackground)
}
#endif
