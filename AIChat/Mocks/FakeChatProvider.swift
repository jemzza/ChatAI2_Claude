#if DEBUG
import Foundation

/// AI-собеседник по сценарию — для тестов, превью и DEBUG launch-аргументов.
final class FakeChatProvider: ChatProvider {
    enum Script: Sendable {
        /// Ответ после задержки.
        case reply(String, delay: Duration = .zero)
        /// Ошибка после задержки.
        case fail(APIError, delay: Duration = .zero)
        /// Не отвечает, пока задачу не отменят.
        case hang
    }

    struct Request: Hashable, Sendable {
        let chatId: UUID
        let text: String
    }

    private struct State {
        var script: Script
        var requests: [Request] = []
    }

    private let state: Locked<State>

    init(script: Script = .reply("Hello")) {
        state = Locked(State(script: script))
    }

    var requests: [Request] { state.withLock(\.requests) }

    func setScript(_ script: Script) {
        state.withLock { $0.script = script }
    }

    func reply(to text: String, inChat chatId: UUID) async throws -> String {
        let script = state.withLock { state in
            state.requests.append(Request(chatId: chatId, text: text))
            return state.script
        }
        switch script {
        case let .reply(answer, delay):
            if delay > .zero { try await Task.sleep(for: delay) }
            return answer
        case let .fail(error, delay):
            if delay > .zero { try await Task.sleep(for: delay) }
            throw error
        case .hang:
            try await Task.sleep(for: .seconds(3600))
            throw CancellationError()
        }
    }
}
#endif
