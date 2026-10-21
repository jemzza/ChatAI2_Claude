import Foundation

/// Чат для списка истории: сам чат и текст последнего непустого сообщения (превью строки).
struct ChatSummary: Identifiable, Hashable, Sendable {
    let chat: Chat
    let lastMessage: String?

    var id: UUID { chat.id }
}
