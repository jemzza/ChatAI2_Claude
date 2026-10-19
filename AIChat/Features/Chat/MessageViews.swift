import SwiftUI

/// Сообщение пользователя: градиентный пузырь на всю ширину, острый правый нижний угол.
struct UserBubble: View {
    let message: Message

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            // Текст сообщения — данные пользователя.
            Text(message.text)
                .font(AppFont.body)
                .foregroundStyle(Color.appAccent)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(
                    LinearGradient(colors: [.appGradientStart.opacity(0.9), .appGradientEnd.opacity(0.9)],
                                   startPoint: .leading, endPoint: .trailing),
                    in: BubbleShape(sharpCorner: .bottomRight)
                )
            if message.status == .pending {
                Label("Will send when online", systemImage: "clock")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.appTextSecondary)
            }
        }
    }
}

/// Ответ ассистента: полупрозрачная карточка, острый левый нижний угол, markdown,
/// под чертой — «копировать» и (у последнего ответа) «перегенерировать».
struct AssistantBubble: View {
    let message: Message
    let canRegenerate: Bool
    let onCopy: () -> Void
    let onRetry: () -> Void

    var body: some View {
        Group {
            if message.status == .generating {
                // «Печатает» — компактная плашка по размеру точек.
                content
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            } else {
                content
                    .padding(16)
                    .frame(maxWidth: 334, alignment: .leading)
            }
        }
        .background(Color.appSurface.opacity(0.5), in: BubbleShape(sharpCorner: .bottomLeft))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        switch message.status {
        case .generating:
            TypingIndicator()
        case .failed, .interrupted:
            ProblemView(text: problemText, onRetry: onRetry)
        default:
            VStack(alignment: .leading, spacing: 16) {
                MarkdownView(text: message.text)
                    .foregroundStyle(Color.appAccent.opacity(0.8))
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 1)
                HStack {
                    iconButton("IconCopy", label: "Copy", action: onCopy)
                    Spacer()
                    if canRegenerate {
                        iconButton("IconRefresh", label: "Regenerate", action: onRetry)
                            .transition(.opacity)
                    }
                }
                .opacity(0.5)
            }
        }
    }

    private var problemText: LocalizedStringKey {
        message.status == .interrupted
            ? "The response was interrupted."
            : ErrorText.key(for: message.failure)
    }

    private func iconButton(_ image: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(image)
                .renderingMode(.template)
                .foregroundStyle(Color.appAccent)
                .frame(width: 24, height: 24)
                .padding(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .padding(-4)
        .accessibilityLabel(Text(label))
    }
}

/// Ошибка ответа: понятный текст и «Try again».
private struct ProblemView: View {
    let text: LocalizedStringKey
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(text)
                    .font(AppFont.subheadline)
                    .foregroundStyle(Color.appAccent.opacity(0.8))
            } icon: {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(AppGradient.primary)
            }
            Button(action: onRetry) {
                Text("Try again")
                    .font(AppFont.subheadlineMedium)
                    .foregroundStyle(Color.appAccent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(AppGradient.primary, in: Capsule())
            }
            .buttonStyle(PressableButtonStyle())
        }
    }
}

/// «Печатает»: три точки, по очереди вспыхивающие градиентом.
struct TypingIndicator: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(index == phase ? AnyShapeStyle(AppGradient.primary) : AnyShapeStyle(Color.white.opacity(0.25)))
                    .frame(width: 8, height: 8)
                    .scaleEffect(index == phase ? 1.25 : 1)
            }
        }
        .frame(height: 20)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(350))
                withAnimation(.easeInOut(duration: 0.3)) { phase = (phase + 1) % 3 }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Generating a response"))
    }
}

/// Скругление 24 у всех углов, кроме одного острого (как «хвостик» пузыря).
struct BubbleShape: Shape {
    enum Corner {
        case bottomLeft
        case bottomRight
    }

    let sharpCorner: Corner
    var radius: CGFloat = AppMetrics.cardRadius

    func path(in rect: CGRect) -> Path {
        var corners: UIRectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
        corners.remove(sharpCorner == .bottomLeft ? .bottomLeft : .bottomRight)
        return Path(UIBezierPath(roundedRect: rect, byRoundingCorners: corners,
                                 cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}

/// Тексты ошибок по таблице маппинга (docs/task.md).
enum ErrorText {
    static func key(for failure: MessageFailure?) -> LocalizedStringKey {
        switch failure?.kind ?? .unknown {
        case .offline: "No internet connection. Check your connection and try again."
        case .rateLimited: "Too many requests. Please wait a moment and try again."
        case .paymentRequired: "The AI service is temporarily unavailable. Please try again later."
        case .unauthorized, .forbidden: "Access to the AI service was denied. Please try again later."
        case .server, .notFound: "The server is having trouble right now. Please try again."
        case .validation, .decoding, .unknown: "Something went wrong. Please try again."
        }
    }
}
