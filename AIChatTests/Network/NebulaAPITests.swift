import Foundation
import Testing
@testable import AIChat

struct NebulaAPITests {
    private struct OK: Decodable { let ok: Bool }

    private final class User: Sendable {
        private let id = Locked("u1")
        var current: String { id.withLock { $0 } }
        func set(_ value: String) { id.withLock { $0 = value } }
    }

    private func api(user: User = User(), status: Int = 200) -> (NebulaAPI, RequestLog) {
        let (session, log) = StubURLProtocol.session { _ in .response(status: status, body: Data(#"{"ok":true}"#.utf8)) }
        let client = APIClient(baseURL: URL(string: "https://example.test/pixverse")!, session: session)
        return (NebulaAPI(client: client, ownerToken: "owner", appID: "com.test.test", userID: { user.current }), log)
    }

    @Test func everyRequestCarriesOwnerTokenAndIdentity() async throws {
        let (api, log) = api()

        let response: OK = try await api.send(.get("api/v1/status", query: [URLQueryItem(name: "id", value: "7")]))

        #expect(response.ok)
        let request = try #require(log.all.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer owner")
        let items = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems
        #expect(items == [URLQueryItem(name: "id", value: "7"), URLQueryItem(name: "user_id", value: "u1"),
                          URLQueryItem(name: "app_id", value: "com.test.test")])
    }

    @Test func userIdIsReadAtRequestTime() async throws {
        let user = User()
        let (api, log) = api(user: user)
        _ = try await api.data(for: .get("a"))
        user.set("u2")
        _ = try await api.data(for: .get("b"))

        let ids = log.all.compactMap { request in
            request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
                .queryItems?.first { $0.name == "user_id" }?.value
        }
        #expect(ids == ["u1", "u2"])
    }

    @Test func multipartPostKeepsBodyAndAddsQuery() async throws {
        var form = MultipartFormData(boundary: "B")
        form.append("1", name: "template_id")
        let (api, log) = api()

        _ = try await api.data(for: .post("api/v1/template2video", multipart: form))

        let request = try #require(log.all.first)
        #expect(request.url?.query == "user_id=u1&app_id=com.test.test")
        #expect(request.httpBody == form.encoded())
    }

    @Test func errorsPassThrough() async {
        let (api, _) = api(status: 402)
        await #expect(throws: APIError(kind: .paymentRequired)) {
            _ = try await api.data(for: .get("x"))
        }
    }
}
