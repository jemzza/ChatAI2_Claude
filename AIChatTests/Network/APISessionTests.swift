import Foundation
import Testing
@testable import AIChat

struct APISessionTests {
    /// Поддельный сервер: `auth/session`, `auth/refresh` и защищённый `data`.
    private final class FakeServer: Sendable {
        struct State {
            var opened = 0
            var refreshed = 0
            var dataCalls = 0
            var issued = 0
            /// Какие access-токены сервер сейчас принимает.
            var valid: Set<String> = []
            var refreshFails = false
            var alwaysUnauthorized = false
            var expiresIn = 3600
        }

        let state = Locked(State())

        func handle(_ request: URLRequest) -> StubURLProtocol.Reply {
            let path = request.url?.path ?? ""
            let auth = request.value(forHTTPHeaderField: "Authorization")
            return state.withLock { state in
                if path.hasSuffix("auth/session") {
                    guard auth == "Bearer owner" else { return .response(status: 401) }
                    state.opened += 1
                    return Self.session(&state, user: Self.userId(request))
                }
                if path.hasSuffix("auth/refresh") {
                    state.refreshed += 1
                    if state.refreshFails { return .response(status: 401) }
                    return Self.session(&state, user: "u1")
                }
                state.dataCalls += 1
                guard !state.alwaysUnauthorized,
                      let token = auth?.replacingOccurrences(of: "Bearer ", with: ""),
                      state.valid.contains(token)
                else { return .response(status: 401) }
                return .response(status: 200, body: Data(#"{"ok":true}"#.utf8))
            }
        }

        private static func session(_ state: inout State, user: String) -> StubURLProtocol.Reply {
            state.issued += 1
            let access = "access-\(state.issued)"
            state.valid = [access]
            let json = #"{"access_token":"\#(access)","refresh_token":"refresh-\#(state.issued)-xxxxxxxxxxxxxxxxxxxx","expires_in":\#(state.expiresIn),"token_type":"Bearer","user_id":"\#(user)","app_id":"com.test.test"}"#
            return .response(status: 201, body: Data(json.utf8))
        }

        private static func userId(_ request: URLRequest) -> String {
            let body = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] }
            return body?["user_id"] ?? "?"
        }
    }

    private struct OK: Decodable { let ok: Bool }

    private final class Clock: Sendable {
        private let date = Locked(Date(timeIntervalSince1970: 1_000_000))
        var now: Date { date.withLock { $0 } }
        func advance(_ seconds: TimeInterval) { date.withLock { $0 = $0.addingTimeInterval(seconds) } }
    }

    private final class User: Sendable {
        private let id = Locked("u1")
        var current: String { id.withLock { $0 } }
        func set(_ value: String) { id.withLock { $0 = value } }
    }

    private struct Harness {
        let server = FakeServer()
        let store = InMemoryTokenStore()
        let clock = Clock()
        let user = User()
        let session: APISession

        init() {
            let server = server, clock = clock, user = user
            let (urlSession, _) = StubURLProtocol.session { server.handle($0) }
            session = APISession(
                client: APIClient(baseURL: URL(string: "https://example.test/dola")!, session: urlSession),
                configuration: .init(ownerToken: "owner", appID: "com.test.test", storageKey: "dola"),
                userID: { user.current },
                store: store,
                now: { clock.now }
            )
        }

        func request() async throws -> OK {
            try await session.send(.get("api/v3/chats"))
        }
    }

    @Test func firstRequestOpensSessionAndStoresTokens() async throws {
        let harness = Harness()

        #expect(try await harness.request().ok)
        #expect(try await harness.request().ok)

        #expect(harness.server.state.withLock(\.opened) == 1)
        let stored = try #require(harness.store.load(key: "dola"))
        #expect(stored.accessToken == "access-1")
        #expect(stored.userId == "u1")
    }

    @Test func unauthorizedRefreshesAndRetriesOnce() async throws {
        let harness = Harness()
        _ = try await harness.request()
        harness.server.state.withLock { $0.valid = [] }  // сервер «забыл» токен

        #expect(try await harness.request().ok)

        harness.server.state.withLock { state in
            #expect(state.refreshed == 1)
            #expect(state.opened == 1)
            #expect(state.dataCalls == 3)
        }
    }

    @Test func persistentUnauthorizedFailsWithoutLooping() async throws {
        let harness = Harness()
        harness.server.state.withLock { $0.alwaysUnauthorized = true }

        await #expect(throws: APIError(kind: .unauthorized)) { try await harness.request() }

        harness.server.state.withLock { state in
            #expect(state.dataCalls == 2)
            #expect(state.refreshed == 1)
        }
    }

    @Test func failedRefreshOpensNewSession() async throws {
        let harness = Harness()
        _ = try await harness.request()
        harness.server.state.withLock { $0.valid = []; $0.refreshFails = true }

        #expect(try await harness.request().ok)

        #expect(harness.server.state.withLock(\.opened) == 2)
        #expect(harness.store.load(key: "dola")?.accessToken == "access-2")
    }

    @Test func expiringTokenIsRefreshedBeforeRequest() async throws {
        let harness = Harness()
        _ = try await harness.request()
        harness.clock.advance(3600 - 30)  // до истечения меньше запаса в 60 с

        _ = try await harness.request()

        harness.server.state.withLock { state in
            #expect(state.refreshed == 1)
            #expect(state.dataCalls == 2)  // без лишнего 401
        }
    }

    @Test func concurrentRequestsShareOneSessionOpening() async throws {
        let harness = Harness()

        try await withThrowingTaskGroup(of: Bool.self) { group in
            for _ in 0..<8 { group.addTask { try await harness.request().ok } }
            for try await ok in group { #expect(ok) }
        }

        #expect(harness.server.state.withLock(\.opened) == 1)
    }

    @Test func otherUserGetsNewSession() async throws {
        let harness = Harness()
        _ = try await harness.request()
        harness.user.set("u2")

        _ = try await harness.request()

        #expect(harness.server.state.withLock(\.opened) == 2)
        #expect(harness.store.load(key: "dola")?.userId == "u2")
    }

    @Test func storedTokensAreReusedAfterRestart() async throws {
        let harness = Harness()
        harness.store.save(SessionTokens(accessToken: "access-0", refreshToken: "r", expiresAt: harness.clock.now
                                            .addingTimeInterval(3600), userId: "u1"), key: "dola")
        harness.server.state.withLock { $0.valid = ["access-0"] }

        _ = try await harness.request()

        #expect(harness.server.state.withLock(\.opened) == 0)
    }

    @Test func wrongOwnerTokenIsUnauthorized() async {
        let server = FakeServer()
        let (urlSession, _) = StubURLProtocol.session { server.handle($0) }
        let session = APISession(
            client: APIClient(baseURL: URL(string: "https://example.test/dola")!, session: urlSession),
            configuration: .init(ownerToken: "wrong", appID: "com.test.test", storageKey: "dola"),
            userID: { "u1" },
            store: InMemoryTokenStore()
        )
        await #expect(throws: APIError(kind: .unauthorized)) {
            let _: OK = try await session.send(.get("api/v3/chats"))
        }
    }
}

/// Keychain в симуляторе (хост — приложение): запись, чтение, обновление, удаление.
struct KeychainTokenStoreTests {
    @Test func roundTrip() {
        let store = KeychainTokenStore(service: "com.labs.fviu.tests.\(UUID().uuidString)")
        let first = SessionTokens(accessToken: "a", refreshToken: "r", expiresAt: Date(timeIntervalSince1970: 10), userId: "u")
        let second = SessionTokens(accessToken: "b", refreshToken: "r2", expiresAt: Date(timeIntervalSince1970: 20), userId: "u")

        #expect(store.load(key: "k") == nil)
        store.save(first, key: "k")
        #expect(store.load(key: "k") == first)
        store.save(second, key: "k")
        #expect(store.load(key: "k") == second)
        store.remove(key: "k")
        #expect(store.load(key: "k") == nil)
    }
}
