import Foundation
import Testing
@testable import AIChat

struct DolaChatProviderTests {
    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name).json"))
    }

    @Test func sendsMessageAndDecodesRealResponse() async throws {
        let body = try fixture("dola_send_message")
        let (session, log) = StubURLProtocol.session { _ in .response(status: 200, body: body) }
        let api = NebulaAPI(client: APIClient(baseURL: URL(string: "https://nebulaapps.site/dola")!, session: session),
                            ownerToken: "owner", appID: "com.test.test", userID: { "user-1" })
        let chatId = UUID(uuidString: "7B1AC4C8-7268-47DC-A6BD-A6EA975EB230")!

        let reply = try await DolaChatProvider(api: api).reply(to: "Hi", inChat: chatId)

        #expect(reply == "Sandbox Dola reply: integration test response.")
        let request = try #require(log.all.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://nebulaapps.site/dola/dola/chats/7b1ac4c8-7268-47dc-a6bd-a6ea975eb230/messages?user_id=user-1&app_id=com.test.test")
        let json = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: String]
        #expect(json == ["message": "Hi"])
    }

    @Test func paymentRequiredIsReported() async {
        let (session, _) = StubURLProtocol.session { _ in
            .response(status: 402, body: Data(#"{"detail":"Insufficient balance for Dola chat"}"#.utf8))
        }
        let api = NebulaAPI(client: APIClient(baseURL: URL(string: "https://nebulaapps.site/dola")!, session: session),
                            ownerToken: "owner", appID: "com.test.test", userID: { "user-1" })
        await #expect(throws: APIError(kind: .paymentRequired)) {
            _ = try await DolaChatProvider(api: api).reply(to: "Hi", inChat: UUID())
        }
    }
}
