import Foundation

/// Ошибка запроса к API. Ничего из ответа сервера (тело, URL, токены) не хранит —
/// текст для пользователя строит UI по `kind`.
struct APIError: Error, Hashable, Sendable {
    let kind: ErrorKind
    /// Значение `retry-after` при 429.
    let retryAfter: Duration?

    init(kind: ErrorKind, retryAfter: Duration? = nil) {
        self.kind = kind
        self.retryAfter = retryAfter
    }
}
