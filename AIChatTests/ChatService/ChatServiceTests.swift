import Foundation
import Testing
@testable import AIChat

@MainActor
struct ChatServiceTests {
    private struct Harness {
        let repository: RecordingRepository
        let provider: FakeChatProvider
        let connectivity: FakeConnectivityMonitor
        let backgroundTasks: ManualBackgroundTasks
        let service: ChatService
    }

    private nonisolated static let fixedNow = Date(timeIntervalSince1970: 1_000_000)

    private func makeHarness(script: FakeChatProvider.Script = .reply("Hello world"),
                             isOnline: Bool = true) throws -> Harness {
        let repository = RecordingRepository(base: GRDBChatRepository(database: try AppDatabase.inMemory()))
        let provider = FakeChatProvider(script: script)
        let connectivity = FakeConnectivityMonitor(isOnline: isOnline)
        let backgroundTasks = ManualBackgroundTasks()
        let dates = SteppingDates(start: Self.fixedNow)
        let service = ChatService(repository: repository, provider: provider, connectivity: connectivity,
                                  backgroundTasks: backgroundTasks, now: { dates.next() })
        return Harness(repository: repository, provider: provider, connectivity: connectivity,
                       backgroundTasks: backgroundTasks, service: service)
    }

    private func messages(
        _ harness: Harness,
        chatId: UUID,
        where predicate: @escaping @Sendable ([Message]) -> Bool
    ) async throws -> [Message] {
        try await firstValue(of: harness.repository.observeMessages(chatId: chatId), where: predicate)
    }

    // MARK: Отправка

    @Test func onlineSendCreatesChatAndStoresReply() async throws {
        let harness = try makeHarness()

        let chatId = try await harness.service.send("Hi there", inChat: nil)

        let messages = try await messages(harness, chatId: chatId) { $0.last?.status == .done }
        #expect(messages.map(\.role) == [.user, .assistant])
        #expect(messages.map(\.text) == ["Hi there", "Hello world"])
        #expect(messages.first?.status == .sent)
        #expect(harness.provider.requests == [FakeChatProvider.Request(chatId: chatId, text: "Hi there")])
        let chats = try await firstValue(of: harness.repository.observeChats())
        #expect(chats.map(\.title) == ["Hi there"])
        // Ответ целиком — одна запись в базу.
        try await waitUntil { !harness.service.isGenerating(chatId: chatId) }
        #expect(harness.repository.updateStatuses == [.done])
        #expect(harness.backgroundTasks.activeCount == 0)
    }

    /// Пока ждём ответ, в базе лежит `generating` — по нему экран показывает анимацию.
    @Test func replyIsGeneratingWhileWaiting() async throws {
        let harness = try makeHarness(script: .hang)

        let chatId = try await harness.service.send("Hi", inChat: nil)

        let messages = try await messages(harness, chatId: chatId) { $0.count == 2 }
        #expect(messages.last?.status == .generating)
        #expect(harness.service.isGenerating(chatId: chatId))
        try await harness.service.deleteChat(id: chatId)
    }

    @Test func offlineSendStaysPendingWithoutRequest() async throws {
        let harness = try makeHarness(isOnline: false)

        let chatId = try await harness.service.send("Hi", inChat: nil)

        let messages = try await messages(harness, chatId: chatId) { !$0.isEmpty }
        #expect(messages.map(\.status) == [.pending])
        #expect(harness.provider.requests.isEmpty)
    }

    @Test(arguments: [
        (APIError(kind: .rateLimited, retryAfter: .seconds(30)), Optional(fixedNow.addingTimeInterval(2 + 30))),
        (APIError(kind: .paymentRequired), nil),
        (APIError(kind: .unauthorized), nil),
        (APIError(kind: .offline), nil),
    ])
    func providerErrorMarksFailed(error: APIError, retryAt: Date?) async throws {
        let harness = try makeHarness(script: .fail(error))

        let chatId = try await harness.service.send("Hi", inChat: nil)

        let messages = try await messages(harness, chatId: chatId) { $0.last?.status == .failed }
        #expect(messages.last?.failure == MessageFailure(kind: error.kind, retryAt: retryAt))
        #expect(messages.last?.text == "")
    }

    // MARK: Retry и Regenerate

    @Test func retryAsksTheSameQuestionAgain() async throws {
        let harness = try makeHarness(script: .fail(APIError(kind: .server)))
        let chatId = try await harness.service.send("Question", inChat: nil)
        let failed = try await messages(harness, chatId: chatId) { $0.last?.status == .failed }
        try await waitUntil { !harness.service.isGenerating(chatId: chatId) }
        harness.provider.setScript(.reply("Answer"))

        try await harness.service.retry(assistantMessageId: try #require(failed.last).id, inChat: chatId)

        let messages = try await messages(harness, chatId: chatId) { $0.last?.status == .done }
        #expect(messages.map(\.text) == ["Question", "Answer"])
        #expect(messages.last?.id == failed.last?.id)
        #expect(messages.last?.failure == nil)
        #expect(harness.provider.requests.map(\.text) == ["Question", "Question"])
    }

    @Test func regenerateReplacesDoneReplyInPlace() async throws {
        let harness = try makeHarness(script: .reply("First answer"))
        let chatId = try await harness.service.send("Question", inChat: nil)
        let done = try await messages(harness, chatId: chatId) { $0.last?.status == .done }
        try await waitUntil { !harness.service.isGenerating(chatId: chatId) }
        harness.provider.setScript(.reply("Second answer"))

        try await harness.service.retry(assistantMessageId: try #require(done.last).id, inChat: chatId)

        let messages = try await messages(harness, chatId: chatId) { $0.last?.text == "Second answer" }
        #expect(messages.count == 2)
        #expect(messages.last?.status == .done)
    }

    @Test func doubleRetryStartsOneRequest() async throws {
        let harness = try makeHarness(script: .fail(APIError(kind: .server)))
        let chatId = try await harness.service.send("Question", inChat: nil)
        let failed = try await messages(harness, chatId: chatId) { $0.last?.status == .failed }
        try await waitUntil { !harness.service.isGenerating(chatId: chatId) }
        harness.provider.setScript(.reply("Answer", delay: .milliseconds(50)))
        let replyId = try #require(failed.last).id

        async let first: Void = harness.service.retry(assistantMessageId: replyId, inChat: chatId)
        async let second: Void = harness.service.retry(assistantMessageId: replyId, inChat: chatId)
        _ = try await (first, second)

        _ = try await messages(harness, chatId: chatId) { $0.last?.status == .done }
        #expect(harness.provider.requests.count == 2)
    }

    // MARK: Outbox

    @Test func outboxSendsPendingOnceInOrderWhenOnline() async throws {
        let harness = try makeHarness(script: .reply("Ok"), isOnline: false)
        let chatId = try await harness.service.send("First", inChat: nil)
        _ = try await harness.service.send("Second", inChat: chatId)
        let run = Task { await harness.service.run() }
        defer { run.cancel() }

        harness.connectivity.setOnline(true)
        // Повторные поводы (foreground, ещё раз сеть) не должны дать второй отправки.
        harness.service.appDidBecomeActive()
        await harness.service.processOutbox()
        harness.connectivity.setOnline(false)
        harness.connectivity.setOnline(true)

        let messages = try await messages(harness, chatId: chatId) {
            $0.count == 4 && $0.allSatisfy { $0.status == .sent || $0.status == .done }
        }
        #expect(messages.map(\.text) == ["First", "Ok", "Second", "Ok"])
        try await waitUntil { !harness.service.isGenerating(chatId: chatId) }
        try await Task.sleep(for: .milliseconds(100))
        #expect(harness.provider.requests.map(\.text) == ["First", "Second"])
    }

    // MARK: Удаление и прерывание

    @Test func deletingChatCancelsRequest() async throws {
        let harness = try makeHarness(script: .hang)
        let chatId = try await harness.service.send("Go", inChat: nil)
        #expect(harness.service.isGenerating(chatId: chatId))

        try await harness.service.deleteChat(id: chatId)

        try await waitUntil { !harness.service.isGenerating(chatId: chatId) }
        #expect(try await firstValue(of: harness.repository.observeChats()).isEmpty)
        #expect(harness.backgroundTasks.activeCount == 0)
    }

    @Test func deleteAllCancelsEveryRequestAndEmptiesRepository() async throws {
        let harness = try makeHarness(script: .hang)
        let first = try await harness.service.send("One", inChat: nil)
        let second = try await harness.service.send("Two", inChat: nil)

        try await harness.service.deleteAll()

        try await waitUntil {
            !harness.service.isGenerating(chatId: first) && !harness.service.isGenerating(chatId: second)
        }
        #expect(try await firstValue(of: harness.repository.observeChats()).isEmpty)
        #expect(harness.backgroundTasks.activeCount == 0)
    }

    /// Чат удалили в обход сервиса — запоздавшая запись получает `MessageNotFound` и глотается.
    @Test func lateReplyToDeletedChatIsSwallowed() async throws {
        let harness = try makeHarness(script: .reply("Late", delay: .milliseconds(100)))
        let chatId = try await harness.service.send("Go", inChat: nil)

        try await harness.repository.deleteChat(id: chatId)

        try await waitUntil { !harness.service.isGenerating(chatId: chatId) }
        #expect(harness.repository.updateStatuses == [.done])
        #expect(harness.backgroundTasks.activeCount == 0)
    }

    @Test func backgroundExpirationMarksInterrupted() async throws {
        let harness = try makeHarness(script: .hang)
        let chatId = try await harness.service.send("Go", inChat: nil)
        try await waitUntil { harness.provider.requests.count == 1 }
        #expect(harness.backgroundTasks.activeCount == 1)

        harness.backgroundTasks.expireAll()

        let messages = try await messages(harness, chatId: chatId) { $0.last?.status == .interrupted }
        #expect(messages.last?.failure == nil)
        try await waitUntil { harness.backgroundTasks.activeCount == 0 }
    }
}
