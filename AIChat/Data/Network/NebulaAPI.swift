import Foundation

/// Авторизованные запросы к сервисам Nebula (Dola, PixVerse) по v1:
/// `Authorization: Bearer <токен владельца>` и query `user_id` / `app_id` в каждом запросе.
struct NebulaAPI: Sendable {
    let client: APIClient
    /// Bearer-токен владельца API (`Secrets.nebulaAPIToken`).
    private let ownerToken: String
    /// `app_id` — bundle id, под которым приложение зарегистрировано в API.
    let appID: String
    /// ID пользователя (Apphud User ID) на момент запроса.
    private let userID: @Sendable () async -> String

    init(client: APIClient, ownerToken: String, appID: String, userID: @escaping @Sendable () async -> String) {
        self.client = client
        self.ownerToken = ownerToken
        self.appID = appID
        self.userID = userID
    }

    /// Запрос с декодированием JSON-ответа.
    func send<Response: Decodable>(_ endpoint: Endpoint, as type: Response.Type = Response.self) async throws
        -> Response {
        try await client.send(authorized(endpoint), accessToken: ownerToken)
    }

    /// Запрос; тело успешного ответа.
    func data(for endpoint: Endpoint) async throws -> Data {
        try await client.data(for: authorized(endpoint), accessToken: ownerToken)
    }

    private func authorized(_ endpoint: Endpoint) async -> Endpoint {
        var endpoint = endpoint
        endpoint.query += [
            URLQueryItem(name: "user_id", value: await userID()),
            URLQueryItem(name: "app_id", value: appID),
        ]
        return endpoint
    }
}
