import Foundation

/// Экран чата. Сообщения читает из базы (`ChatRepository`), отправляет через `ChatSession`;
/// идёт ли генерация — по статусу `generating` последнего ответа. Без подписки отправка
/// открывает пейвол, а введённый текст остаётся в поле (заметка к макету).
@MainActor
final class ChatViewModel: ObservableObject {
    /// Подсказки пустого чата: подставляются в поле, а не отправляются сразу.
    static let suggestions: [LocalizedStringResource] = [
        "Help me write an email", "Explain it simply", "Translate a text", "Plan my day",
    ]

    @Published private(set) var chatId: UUID?
    @Published private(set) var chat: Chat?
    @Published private(set) var messages: [Message] = []
    @Published var draft: String
    @Published var toast: ToastMessage?

    private let repository: any ChatRepository
    private let session: any ChatSession
    private let subscription: any SubscriptionService
    private let copyToPasteboard: @MainActor (String) -> Bool
    private let now: () -> Date
    /// Открыть пейвол (премиум-действие без подписки).
    var onPaywall: () -> Void = {}

    init(
        chatId: UUID?,
        prompt: String?,
        repository: any ChatRepository,
        session: any ChatSession,
        subscription: any SubscriptionService,
        copyToPasteboard: @escaping @MainActor (String) -> Bool,
        now: @escaping () -> Date = Date.init
    ) {
        self.chatId = chatId
        draft = prompt ?? ""
        self.repository = repository
        self.session = session
        self.subscription = subscription
        self.copyToPasteboard = copyToPasteboard
        self.now = now
    }

    // MARK: Состояние экрана

    var isEmpty: Bool { messages.isEmpty }

    /// Ждём ответ — Send неактивна, внизу анимация «печатает».
    var isGenerating: Bool { messages.contains { $0.status == .generating } }

    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isGenerating
    }

    /// Дата под названием: создание чата, для нового — сегодня.
    var date: Date { chat?.createdAt ?? now() }

    var isPinned: Bool { chat?.pinnedAt != nil }

    /// «Regenerate» — только у последнего ответа (заметка к макету).
    func canRegenerate(_ message: Message) -> Bool {
        message.role == .assistant && message.status == .done
            && message.id == messages.last(where: { $0.role == .assistant })?.id
    }

    // MARK: Наблюдение

    /// Живёт, пока экран на экране и `chatId` не сменился (`.task(id:)`).
    func observe() async {
        guard let chatId else { return }
        async let chats: Void = observeChat(chatId)
        async let messages: Void = observeMessages(chatId)
        _ = await (chats, messages)
    }

    private func observeChat(_ chatId: UUID) async {
        for await chats in repository.observeChats() {
            chat = chats.first { $0.id == chatId }
        }
    }

    private func observeMessages(_ chatId: UUID) async {
        for await messages in repository.observeMessages(chatId: chatId) {
            self.messages = messages
        }
    }

    // MARK: Действия

    func useSuggestion(_ suggestion: LocalizedStringResource) {
        draft = String(localized: suggestion)
    }

    func send() async {
        guard canSend else { return }
        guard subscription.isPremium else {
            onPaywall()
            return
        }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = ""
        do {
            let sentChatId = try await session.send(text, inChat: chatId)
            if chatId == nil { chatId = sentChatId }
        } catch {
            // Не записалось в базу — возвращаем текст, чтобы не потерять.
            draft = text
            toast = ToastMessage(kind: .failure, text: "Couldn't send message")
        }
    }

    func copy(_ message: Message) {
        let copied = !message.text.isEmpty && copyToPasteboard(message.text)
        toast = copied ? ToastMessage(kind: .success, text: "Copied") : ToastMessage(kind: .failure, text: "Copy failed")
    }

    // MARK: Меню чата

    /// Есть что показывать в меню «…» — чат уже создан.
    var hasMenu: Bool { chat != nil }

    /// Текст для «Share»: переписка целиком, вопросы и ответы по порядку.
    var shareText: String {
        messages
            .filter { !$0.text.isEmpty && $0.status != .generating }
            .map(\.text)
            .joined(separator: "\n\n")
    }

    func togglePin() async {
        guard let chatId else { return }
        try? await repository.setPinned(chatId: chatId, at: isPinned ? nil : now())
    }

    /// Удаляет чат (и отменяет его запрос). Экран после этого закрывается.
    func deleteChat() async -> Bool {
        guard let chatId else { return false }
        do {
            try await session.deleteChat(id: chatId)
            return true
        } catch {
            toast = ToastMessage(kind: .failure, text: "Couldn't delete chat")
            return false
        }
    }

    /// «Retry» у ошибки и «Regenerate» у последнего ответа.
    func retry(_ message: Message) async {
        guard let chatId else { return }
        guard subscription.isPremium else {
            onPaywall()
            return
        }
        try? await session.retry(assistantMessageId: message.id, inChat: chatId)
    }
}
