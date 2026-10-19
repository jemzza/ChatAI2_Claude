import Foundation

/// Вид ошибки сети/API. Сырое значение хранится в базе (`MessageRecord`) —
/// неизвестное значение при чтении становится `unknown`.
enum ErrorKind: String, Hashable, Sendable {
    /// Нет сети.
    case offline
    /// 401 — сессия не открылась или не обновилась.
    case unauthorized
    /// 402 — у владельца API кончились кредиты.
    case paymentRequired
    /// 403.
    case forbidden
    /// 404 — например, генерация видео не найдена.
    case notFound
    /// 422 — сервер не принял параметры запроса.
    case validation
    /// 429 — слишком много запросов.
    case rateLimited
    /// 5xx.
    case server
    /// Ответ пришёл, но не разобрался.
    case decoding
    case unknown
}

/// Причина ошибки ответа. Хранится вместе с сообщением, чтобы
/// «Try again in N s» оставалась верной и после перезапуска.
struct MessageFailure: Hashable, Sendable {
    let kind: ErrorKind
    /// Когда можно повторить (из `retry-after` при 429).
    let retryAt: Date?

    init(kind: ErrorKind, retryAt: Date? = nil) {
        self.kind = kind
        self.retryAt = retryAt
    }
}
