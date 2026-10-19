import Foundation
import Testing
@testable import AIChat

/// Запоминает события `ChatService` и сколько фоновых задач было открыто в этот момент.
@MainActor
private final class RecordingEvents: ChatEventHandling {
    var backgroundTasks: ManualBackgroundTasks?
    private(set) var replies: [(chatId: UUID, text: String, activeBackgroundTasks: Int)] = []
    private(set) var queuedCounts: [Int] = []

    func replyDidFinish(chatId: UUID, text: String) async {
        replies.append((chatId, text, backgroundTasks?.activeCount ?? 0))
    }

    func queuedMessagesDidSend(count: Int) async {
        queuedCounts.append(count)
    }
}

@MainActor
struct ChatServiceEventTests {
    private struct Harness {
        let repository: any ChatRepository
        let provider: FakeChatProvider
        let connectivity: FakeConnectivityMonitor
        let backgroundTasks: ManualBackgroundTasks
        let events: RecordingEvents
        let service: ChatService
    }

    private func makeHarness(script: FakeChatProvider.Script = .reply("Hello world"),
                             isOnline: Bool = true) throws -> Harness {
        let repository = GRDBChatRepository(database: try AppDatabase.inMemory())
        let provider = FakeChatProvider(script: script)
        let connectivity = FakeConnectivityMonitor(isOnline: isOnline)
        let backgroundTasks = ManualBackgroundTasks()
        let events = RecordingEvents()
        events.backgroundTasks = backgroundTasks
        let dates = SteppingDates(start: Date(timeIntervalSince1970: 1_000_000))
        let service = ChatService(repository: repository, provider: provider, connectivity: connectivity,
                                  backgroundTasks: backgroundTasks, eventHandler: events,
                                  now: { dates.next() })
        return Harness(repository: repository, provider: provider, connectivity: connectivity,
                       backgroundTasks: backgroundTasks, events: events, service: service)
    }

    @Test func finishedReplyIsReportedWhileBackgroundTimeIsHeld() async throws {
        let harness = try makeHarness()

        let chatId = try await harness.service.send("Hi", inChat: nil)
        try await waitUntil { !harness.service.isGenerating(chatId: chatId) }

        #expect(harness.events.replies.map(\.chatId) == [chatId])
        #expect(harness.events.replies.map(\.text) == ["Hello world"])
        // Уведомление ставится до `endTask` — иначе система может усыпить приложение раньше.
        #expect(harness.events.replies.map(\.activeBackgroundTasks) == [1])
        #expect(harness.events.queuedCounts.isEmpty)
    }

    @Test func failedReplyIsNotReported() async throws {
        let harness = try makeHarness(script: .fail(APIError(kind: .server)))

        let chatId = try await harness.service.send("Hi", inChat: nil)

        try await waitUntil { !harness.service.isGenerating(chatId: chatId) }
        #expect(harness.events.replies.isEmpty)
    }

    @Test func replyInterruptedBySystemIsNotReported() async throws {
        let harness = try makeHarness(script: .hang)
        let chatId = try await harness.service.send("Hi", inChat: nil)
        try await waitUntil { harness.provider.requests.count == 1 }

        harness.backgroundTasks.expireAll()

        try await waitUntil { !harness.service.isGenerating(chatId: chatId) }
        #expect(harness.events.replies.isEmpty)
    }

    @Test func outboxReportsOnceWithNumberOfSentMessages() async throws {
        let harness = try makeHarness(script: .reply("Ok"), isOnline: false)
        let chatId = try await harness.service.send("First", inChat: nil)
        _ = try await harness.service.send("Second", inChat: chatId)
        _ = try await harness.service.send("Other chat", inChat: nil)

        harness.connectivity.setOnline(true)
        await harness.service.processOutbox()

        #expect(harness.events.queuedCounts == [3])
        #expect(harness.events.replies.count == 3)

        // Нечего отправлять — нет и события.
        await harness.service.processOutbox()
        #expect(harness.events.queuedCounts == [3])
    }
}
