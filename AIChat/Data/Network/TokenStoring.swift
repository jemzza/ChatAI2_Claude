import Foundation

/// Токены клиентской сессии API (`POST /api/v3/auth/session`).
struct SessionTokens: Codable, Hashable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    /// Для какого пользователя (Apphud User ID) открыта сессия.
    let userId: String
}

/// Хранилище токенов. В приложении — Keychain, в тестах — память.
protocol TokenStoring: Sendable {
    func load(key: String) -> SessionTokens?
    func save(_ tokens: SessionTokens, key: String)
    func remove(key: String)
}
