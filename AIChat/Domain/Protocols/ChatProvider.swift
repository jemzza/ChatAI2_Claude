import Foundation

/// AI-собеседник. Контекст переписки держит сервер по `chatId` — отправляем только
/// новое сообщение пользователя, ответ приходит целиком.
protocol ChatProvider: Sendable {
    /// - Throws: `APIError`; отмена задачи — `CancellationError`.
    func reply(to text: String, inChat chatId: UUID) async throws -> String
}
