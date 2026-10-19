import Foundation

/// Авторизованные запросы к одному сервису (Dola или PixVerse).
///
/// Владельческий Bearer-токен уходит только в `auth/session`; дальше — короткий access-токен
/// клиентской сессии. Токены лежат в `TokenStoring` (Keychain). Истёк — обновляем заранее;
/// сервер ответил 401 — обновляем (refresh, при неудаче — новая сессия) и повторяем запрос
/// ровно один раз. Параллельные запросы ждут одно и то же обновление.
actor APISession {
    struct Configuration: Sendable {
        /// Bearer-токен владельца API (`Secrets.nebulaAPIToken`).
        let ownerToken: String
        /// `app_id` — bundle id, под которым приложение зарегистрировано в API.
        let appID: String
        /// Ключ токенов в хранилище — свой у каждого сервиса.
        let storageKey: String
        /// За сколько до истечения обновлять токен.
        var refreshMargin: TimeInterval = 60
    }

    private struct OpenSessionRequest: Encodable {
        let userId: String
        let appId: String
    }

    private struct RefreshRequest: Encodable {
        let refreshToken: String
    }

    private struct SessionResponse: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int
        let userId: String
    }

    let client: APIClient
    private let configuration: Configuration
    private let userID: @Sendable () async -> String
    private let store: any TokenStoring
    private let now: @Sendable () -> Date

    private var tokens: SessionTokens?
    private var didLoadStoredTokens = false
    private var renewal: Task<SessionTokens, Error>?

    init(
        client: APIClient,
        configuration: Configuration,
        userID: @escaping @Sendable () async -> String,
        store: any TokenStoring,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.client = client
        self.configuration = configuration
        self.userID = userID
        self.store = store
        self.now = now
    }

    /// Авторизованный запрос с декодированием JSON-ответа.
    nonisolated func send<Response: Decodable>(_ endpoint: Endpoint, as type: Response.Type = Response.self)
        async throws -> Response {
        let data = try await data(for: endpoint)
        do {
            return try APIClient.decoder.decode(Response.self, from: data)
        } catch {
            throw APIError(kind: .decoding)
        }
    }

    /// Авторизованный запрос; тело успешного ответа.
    func data(for endpoint: Endpoint) async throws -> Data {
        let current = try await validTokens()
        do {
            return try await client.data(for: endpoint, accessToken: current.accessToken)
        } catch let error as APIError where error.kind == .unauthorized {
            let renewed = try await renew(replacing: current)
            return try await client.data(for: endpoint, accessToken: renewed.accessToken)
        }
    }

    // MARK: Токены

    private func validTokens() async throws -> SessionTokens {
        if !didLoadStoredTokens {
            didLoadStoredTokens = true
            tokens = store.load(key: configuration.storageKey)
        }
        let user = await userID()
        if let tokens, tokens.userId == user, !isExpiring(tokens) {
            return tokens
        }
        return try await renew(replacing: tokens)
    }

    /// Обновляет `stale`. Если его уже заменили (другой запрос успел обновить) — отдаёт новые.
    private func renew(replacing stale: SessionTokens?) async throws -> SessionTokens {
        if let renewal {
            return try await renewal.value
        }
        if let tokens, tokens != stale, !isExpiring(tokens) {
            return tokens
        }
        let task = Task { try await self.performRenewal(stale) }
        renewal = task
        defer { renewal = nil }
        let renewed = try await task.value
        tokens = renewed
        store.save(renewed, key: configuration.storageKey)
        return renewed
    }

    private func performRenewal(_ stale: SessionTokens?) async throws -> SessionTokens {
        let user = await userID()
        if let stale, stale.userId == user {
            do {
                return try await refresh(stale)
            } catch let error as APIError where error.kind != .offline {
                // refresh-токен отозван или истёк — открываем сессию заново.
            }
        }
        return try await openSession(userId: user)
    }

    private func openSession(userId: String) async throws -> SessionTokens {
        let endpoint = try Endpoint.post("api/v3/auth/session",
                                         json: OpenSessionRequest(userId: userId, appId: configuration.appID))
        let response: SessionResponse = try await client.send(endpoint, accessToken: configuration.ownerToken)
        return tokens(from: response)
    }

    private func refresh(_ stale: SessionTokens) async throws -> SessionTokens {
        let endpoint = try Endpoint.post("api/v3/auth/refresh", json: RefreshRequest(refreshToken: stale.refreshToken))
        let response: SessionResponse = try await client.send(endpoint)
        return tokens(from: response)
    }

    private func tokens(from response: SessionResponse) -> SessionTokens {
        SessionTokens(accessToken: response.accessToken,
                      refreshToken: response.refreshToken,
                      expiresAt: now().addingTimeInterval(TimeInterval(response.expiresIn)),
                      userId: response.userId)
    }

    private func isExpiring(_ tokens: SessionTokens) -> Bool {
        tokens.expiresAt.timeIntervalSince(now()) < configuration.refreshMargin
    }
}
