import Foundation
import Testing
@testable import AIChat

struct FakeChatProviderTests {
    @Test func repliesAndRecordsRequests() async throws {
        let provider = FakeChatProvider(script: .reply("Hello"))
        let chatId = UUID()

        #expect(try await provider.reply(to: "Hi", inChat: chatId) == "Hello")
        #expect(provider.requests == [FakeChatProvider.Request(chatId: chatId, text: "Hi")])
    }

    @Test func failsWithScriptedError() async {
        let provider = FakeChatProvider(script: .fail(APIError(kind: .rateLimited, retryAfter: .seconds(12))))
        await #expect(throws: APIError(kind: .rateLimited, retryAfter: .seconds(12))) {
            _ = try await provider.reply(to: "Hi", inChat: UUID())
        }
    }

    @Test func hangingReplyEndsOnCancellation() async {
        let provider = FakeChatProvider(script: .hang)
        let task = Task { try await provider.reply(to: "Hi", inChat: UUID()) }
        try? await Task.sleep(for: .milliseconds(30))
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }
}

struct FakeConnectivityMonitorTests {
    @Test func emitsCurrentValueThenOnlyChanges() async throws {
        let monitor = FakeConnectivityMonitor(isOnline: true)
        var iterator = monitor.updates().makeAsyncIterator()
        #expect(await iterator.next() == true)

        monitor.setOnline(true)   // без изменений — не эмитится
        monitor.setOnline(false)
        monitor.setOnline(true)

        #expect(await iterator.next() == false)
        #expect(await iterator.next() == true)
        #expect(monitor.isOnline)
    }

    @Test func supportsSeveralSubscribers() async throws {
        let monitor = FakeConnectivityMonitor(isOnline: true)
        let first = monitor.updates()
        let second = monitor.updates()

        monitor.setOnline(false)

        #expect(try await firstValue(of: first) { !$0 } == false)
        #expect(try await firstValue(of: second) { !$0 } == false)
    }
}

struct PreviewDataTests {
    @Test func coversEveryMessageStatus() {
        let statuses = Set(PreviewData.messages.map(\.status))
        #expect(statuses == [.pending, .sent, .generating, .done, .cancelled, .failed, .interrupted])
    }

    @Test func seedsRepository() async throws {
        let repository = PreviewData.repository()
        let chats = try await firstValue(of: repository.observeChats())
        #expect(chats.count == PreviewData.chats.count)
    }
}
