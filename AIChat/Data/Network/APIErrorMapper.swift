import Foundation

/// Перевод ответов и сетевых ошибок в `APIError` (таблица «Маппинг ошибок» в docs/task.md).
enum APIErrorMapper {
    /// `nil` — код успешный (2xx).
    static func error(statusCode: Int, headers: [AnyHashable: Any]) -> APIError? {
        switch statusCode {
        case 200..<300: nil
        case 401: APIError(kind: .unauthorized)
        case 402: APIError(kind: .paymentRequired)
        case 403: APIError(kind: .forbidden)
        case 404: APIError(kind: .notFound)
        case 422: APIError(kind: .validation)
        case 429: APIError(kind: .rateLimited, retryAfter: retryAfter(headers))
        case 500..<600: APIError(kind: .server)
        default: APIError(kind: .unknown)
        }
    }

    /// Ошибка транспорта. Отмена сюда не попадает — её клиент превращает в `CancellationError`.
    static func error(_ error: URLError) -> APIError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .timedOut,
             .cannotFindHost, .cannotConnectToHost, .internationalRoamingOff:
            APIError(kind: .offline)
        default:
            APIError(kind: .unknown)
        }
    }

    /// `retry-after` в секундах; HTTP-дату не разбираем.
    private static func retryAfter(_ headers: [AnyHashable: Any]) -> Duration? {
        let value = headers.first { ($0.key as? String)?.lowercased() == "retry-after" }?.value as? String
        guard let seconds = value.flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }), seconds > 0 else {
            return nil
        }
        return .seconds(seconds)
    }
}
