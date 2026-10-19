import Foundation

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
}

/// Тело запроса.
enum RequestBody: Sendable {
    case none
    /// Уже закодированный JSON.
    case json(Data)
    case multipart(MultipartFormData)
}

/// Описание запроса относительно базового URL сервиса. Авторизацию добавляет клиент.
struct Endpoint: Sendable {
    var method: HTTPMethod
    /// Путь от базового URL, например `api/v3/status`.
    var path: String
    var query: [URLQueryItem] = []
    var body: RequestBody = .none

    static func get(_ path: String, query: [URLQueryItem] = []) -> Endpoint {
        Endpoint(method: .get, path: path, query: query)
    }

    /// POST с JSON-телом (`snake_case`, как ждёт API).
    static func post(_ path: String, query: [URLQueryItem] = [], json: some Encodable) throws -> Endpoint {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return Endpoint(method: .post, path: path, query: query, body: .json(try encoder.encode(json)))
    }

    static func post(_ path: String, query: [URLQueryItem] = [], multipart: MultipartFormData) -> Endpoint {
        Endpoint(method: .post, path: path, query: query, body: .multipart(multipart))
    }

    /// Собирает `URLRequest`. `nil` — путь или query не сложились в URL.
    func urlRequest(baseURL: URL, accessToken: String?, timeout: TimeInterval) -> URLRequest? {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path),
                                             resolvingAgainstBaseURL: false)
        else { return nil }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        switch body {
        case .none:
            break
        case let .json(data):
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = data
        case let .multipart(form):
            request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
            request.httpBody = form.encoded()
        }
        return request
    }
}
