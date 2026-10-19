import Foundation
import Testing
@testable import AIChat

struct APIClientTests {
    private struct Echo: Codable, Equatable {
        let chatId: String
        let assistantMessage: String
    }

    private let baseURL = URL(string: "https://example.test/dola")!

    private func client(_ handler: @escaping StubURLProtocol.Handler) -> (APIClient, RequestLog) {
        let (session, log) = StubURLProtocol.session(handler)
        return (APIClient(baseURL: baseURL, session: session), log)
    }

    // MARK: Запрос

    @Test func getBuildsURLWithQueryAndBearer() async throws {
        let (client, log) = client { _ in .response(status: 200, body: Data("{}".utf8)) }

        _ = try await client.data(for: .get("api/v3/status", query: [URLQueryItem(name: "id", value: "42")]),
                                  accessToken: "token")

        let request = try #require(log.all.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://example.test/dola/api/v3/status?id=42")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
    }

    @Test func requestWithoutTokenHasNoAuthorization() async throws {
        let (client, log) = client { _ in .response(status: 200) }
        _ = try await client.data(for: .get("health"))
        #expect(try #require(log.all.first).value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func postSendsSnakeCaseJSON() async throws {
        struct Body: Encodable { let userId: String; let appId: String }
        let (client, log) = client { _ in .response(status: 200) }

        _ = try await client.data(for: try .post("api/v3/auth/session", json: Body(userId: "u1", appId: "com.test.test")))

        let request = try #require(log.all.first)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let json = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: String]
        #expect(json == ["user_id": "u1", "app_id": "com.test.test"])
    }

    @Test func multipartContainsFieldsAndFile() async throws {
        var form = MultipartFormData(boundary: "XYZ")
        form.append("7", name: "template_id")
        form.append(Data([0xFF, 0xD8]), name: "image", fileName: "photo.jpg", mimeType: "image/jpeg")
        let (client, log) = client { _ in .response(status: 201) }

        _ = try await client.data(for: .post("api/v3/template2video", multipart: form))

        let request = try #require(log.all.first)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "multipart/form-data; boundary=XYZ")
        var expected = Data("""
            --XYZ\r
            Content-Disposition: form-data; name="template_id"\r
            \r
            7\r
            --XYZ\r
            Content-Disposition: form-data; name="image"; filename="photo.jpg"\r
            Content-Type: image/jpeg\r
            \r

            """.utf8)
        expected.append(contentsOf: [0xFF, 0xD8])
        expected.append(Data("\r\n--XYZ--\r\n".utf8))
        #expect(request.httpBody == expected)
    }

    // MARK: Ответ

    @Test func decodesSnakeCaseResponse() async throws {
        let body = Data(#"{"chat_id":"c1","assistant_message":"Hi"}"#.utf8)
        let (client, _) = client { _ in .response(status: 200, body: body) }

        let echo: Echo = try await client.send(.get("x"))

        #expect(echo == Echo(chatId: "c1", assistantMessage: "Hi"))
    }

    @Test func malformedBodyIsDecodingError() async {
        let (client, _) = client { _ in .response(status: 200, body: Data("<html>".utf8)) }
        await #expect(throws: APIError(kind: .decoding)) {
            let _: Echo = try await client.send(.get("x"))
        }
    }

    @Test(arguments: [
        (401, ErrorKind.unauthorized), (402, .paymentRequired), (403, .forbidden), (404, .notFound),
        (422, .validation), (500, .server), (503, .server), (418, .unknown),
    ])
    func statusCodeMapsToKind(status: Int, kind: ErrorKind) async {
        let (client, _) = client { _ in .response(status: status, body: Data(#"{"detail":"secret"}"#.utf8)) }
        await #expect(throws: APIError(kind: kind)) {
            _ = try await client.data(for: .get("x"))
        }
    }

    @Test func rateLimitReadsRetryAfterSeconds() async {
        let (client, _) = client { _ in .response(status: 429, headers: ["Retry-After": "30"]) }
        await #expect(throws: APIError(kind: .rateLimited, retryAfter: .seconds(30))) {
            _ = try await client.data(for: .get("x"))
        }
    }

    @Test(arguments: [
        (URLError.Code.notConnectedToInternet, ErrorKind.offline), (.timedOut, .offline),
        (.cannotFindHost, .offline), (.networkConnectionLost, .offline), (.badServerResponse, .unknown),
    ])
    func transportErrorMapsToKind(code: URLError.Code, kind: ErrorKind) async {
        let (client, _) = client { _ in .failure(code) }
        await #expect(throws: APIError(kind: kind)) {
            _ = try await client.data(for: .get("x"))
        }
    }

    @Test func cancelledRequestIsCancellationNotError() async {
        let (client, _) = client { _ in .failure(.cancelled) }
        await #expect(throws: CancellationError.self) {
            _ = try await client.data(for: .get("x"))
        }
    }

    /// Текст ошибки не содержит ни тела ответа, ни URL, ни токена.
    @Test func errorDescriptionLeaksNothing() async throws {
        let (client, _) = client { _ in .response(status: 402, body: Data(#"{"detail":"balance-secret"}"#.utf8)) }
        do {
            _ = try await client.data(for: .get("x", query: [URLQueryItem(name: "q", value: "query-secret")]),
                                      accessToken: "token-secret")
            Issue.record("Ожидалась ошибка")
        } catch {
            let text = String(describing: error) + error.localizedDescription
            #expect(!text.contains("secret"))
        }
    }
}
