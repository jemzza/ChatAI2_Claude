import SwiftUI
import UIKit

/// Экран AI-чата (макеты «AI Chat — …»): шапка и поле ввода закреплены, лента прокручивается.
struct ChatView: View {
    @StateObject private var model: ChatViewModel
    @EnvironmentObject private var router: AppRouter
    @FocusState private var isInputFocused: Bool
    private let subscription: any SubscriptionService

    init(chatId: UUID?, prompt: String?, dependencies: AppDependencies) {
        subscription = dependencies.subscription
        _model = StateObject(wrappedValue: ChatViewModel(
            chatId: chatId,
            prompt: prompt,
            repository: dependencies.repository,
            session: dependencies.chat,
            subscription: dependencies.subscription,
            copyToPasteboard: { text in
                UIPasteboard.general.string = text
                return UIPasteboard.general.string == text
            }
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            ChatHeader(title: "AI Chat", date: model.date, isPinned: model.isPinned) { router.pop() } trailing: {
                Color.clear.frame(width: 40, height: 40)
            }
            Group {
                if model.isEmpty {
                    emptyState
                } else {
                    messageList
                }
            }
            .frame(maxHeight: .infinity)
            MessageInputBar(text: $model.draft, placeholder: "How can I help you?",
                            isSendEnabled: model.canSend, focus: $isInputFocused) {
                Task { await model.send() }
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .toast($model.toast)
        .task(id: model.chatId) { await model.observe() }
        .onAppear {
            model.onPaywall = { router.showPaywall(from: .premiumAction) }
            // Новый чат открывается с клавиатурой (заметка к макету).
            if model.chatId == nil { isInputFocused = true }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text(Self.greeting)
                    .font(AppFont.title3)
                    .foregroundStyle(Color.appAccent)
                Text("Pick a suggestion below or ask your own question")
                    .font(AppFont.subheadline)
                    .foregroundStyle(Color.appAccent.opacity(0.5))
            }
            .multilineTextAlignment(.center)
            FlowLayout(spacing: 8) {
                ForEach(ChatViewModel.suggestions, id: \.key) { suggestion in
                    ChipButton(title: String(localized: suggestion), style: .suggestion) {
                        model.useSuggestion(suggestion)
                        isInputFocused = true
                    }
                }
            }
        }
        .padding(.horizontal, AppMetrics.sideInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { isInputFocused = false }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 24) {
                    ForEach(model.messages) { message in
                        row(message)
                            .id(message.id)
                            .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .bottom)),
                                                    removal: .opacity))
                    }
                }
                .padding(.horizontal, AppMetrics.sideInset)
                .padding(.vertical, 24)
                .animation(.easeOut(duration: 0.3), value: model.messages)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear { scrollToBottom(proxy, animated: false) }
            .onChange(of: model.messages.last) { _ in scrollToBottom(proxy, animated: true) }
            .onChange(of: isInputFocused) { focused in
                if focused { scrollToBottom(proxy, animated: true) }
            }
        }
    }

    @ViewBuilder
    private func row(_ message: Message) -> some View {
        switch message.role {
        case .user:
            UserBubble(message: message)
        case .assistant:
            AssistantBubble(
                message: message,
                canRegenerate: model.canRegenerate(message),
                onCopy: { model.copy(message) },
                onRetry: { Task { await model.retry(message) } }
            )
        }
    }

    /// «Your **AI assistant** for anything»: одна строка каталога, выделение — цветом бренда.
    private static var greeting: AttributedString {
        var text = AttributedString(localized: "Your **AI assistant** for anything")
        for run in text.runs where run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
            text[run.range].foregroundColor = .appGradientStart
            text[run.range].inlinePresentationIntent = nil
        }
        return text
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let last = model.messages.last else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(last.id, anchor: .bottom) }
        } else {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }
}

/// Шапка чата: назад, аватар, «AI Chat» + дата (+ значок закрепления), справа — действия.
struct ChatHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    let date: Date
    let isPinned: Bool
    let onBack: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 0) {
            BackButton(action: onBack)
                .frame(width: 24)
                .padding(.trailing, 24)
            HStack(spacing: 12) {
                Image("IconSparkles")
                    .frame(width: 24, height: 24)
                    .frame(width: 32, height: 32)
                    .background(AppGradient.primary, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(AppFont.navigationTitle)
                        if isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 12))
                                .rotationEffect(.degrees(45))
                                .opacity(0.3)
                                .accessibilityLabel(Text("Pinned"))
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    Text(date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year()))
                        .font(AppFont.subheadline)
                        .opacity(0.3)
                }
                .foregroundStyle(Color.appAccent)
            }
            Spacer()
            trailing()
        }
        .padding(16)
        .background(Color.appSurface.opacity(0.4).ignoresSafeArea(edges: .top))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isPinned)
    }
}

/// Перенос чипов по строкам с выравниванием по центру (`Layout` — iOS 16).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX + (bounds.width - row.width) / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
