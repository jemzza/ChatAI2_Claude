import Foundation

/// То, что экранам нужно от `ChatService` сверх чтения из `ChatRepository`.
/// Реализация — `ChatService`.
@MainActor
protocol ChatSession: AnyObject {
    /// Отправляет сообщение пользователя. Есть сеть — сообщение `sent` и ответ `generating`
    /// (запросом владеет сервис); нет — сообщение `pending`, уйдёт само, когда появится сеть.
    /// - Parameter chatId: `nil` — новый чат: создаётся вместе с первым сообщением.
    /// - Returns: id чата, в который ушло сообщение.
    func send(_ text: String, inChat chatId: UUID?) async throws -> UUID

    /// «Retry» у ошибки и «Regenerate» у готового ответа: перезапрашивает ответ на тот же вопрос
    /// в том же сообщении. Повторное нажатие во время генерации ничего не делает (`claimRetry`).
    func retry(assistantMessageId: UUID, inChat chatId: UUID) async throws

    /// Удаляет чат и отменяет его запрос, если он идёт.
    func deleteChat(id: UUID) async throws

    /// Отменяет все запросы и удаляет все чаты, папки и сообщения.
    func deleteAll() async throws
}
