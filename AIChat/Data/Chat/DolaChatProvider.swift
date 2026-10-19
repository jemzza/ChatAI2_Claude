import Foundation

/// `ChatProvider` на Dola: `POST /dola/chats/{chat_id}/messages`.
/// Контекст переписки сервер хранит сам по паре `chat_id` + `user_id`.
struct DolaChatProvider: ChatProvider {
    private struct Request: Encodable {
        let message: String
    }

    private struct Response: Decodable {
        let assistantMessage: String
    }

    let api: NebulaAPI

    func reply(to text: String, inChat chatId: UUID) async throws -> String {
        let endpoint = try Endpoint.post("dola/chats/\(chatId.uuidString.lowercased())/messages",
                                         json: Request(message: text))
        let response: Response = try await api.send(endpoint)
        return response.assistantMessage
    }
}
