import Foundation

/// HTTP-клиент одного сервиса (Dola или PixVerse): собирает запрос из `Endpoint`,
/// выполняет его и переводит ошибки в `APIError`. Отмена `Task` — `CancellationError`.
final class APIClient: Sendable {
    let baseURL: URL
    private let session: URLSession
    private let timeout: TimeInterval

    init(baseURL: URL, session: URLSession = .shared, timeout: TimeInterval = 60) {
        self.baseURL = baseURL
        self.session = session
        self.timeout = timeout
    }

    /// Выполняет запрос и декодирует JSON-ответ (`snake_case` → `camelCase`).
    func send<Response: Decodable>(
        _ endpoint: Endpoint,
        accessToken: String? = nil,
        as type: Response.Type = Response.self
    ) async throws -> Response {
        let data = try await data(for: endpoint, accessToken: accessToken)
        do {
            return try Self.decoder.decode(Response.self, from: data)
        } catch {
            throw APIError(kind: .decoding)
        }
    }

    /// Выполняет запрос; успешный (2xx) ответ — тело, иначе `APIError`.
    func data(for endpoint: Endpoint, accessToken: String? = nil) async throws -> Data {
        guard let request = endpoint.urlRequest(baseURL: baseURL, accessToken: accessToken, timeout: timeout) else {
            throw APIError(kind: .unknown)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw APIErrorMapper.error(error)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw APIError(kind: .unknown)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError(kind: .unknown) }
        if let error = APIErrorMapper.error(statusCode: http.statusCode, headers: http.allHeaderFields) {
            throw error
        }
        return data
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}
