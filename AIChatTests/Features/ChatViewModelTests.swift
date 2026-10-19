import Foundation
import Testing
@testable import AIChat

@MainActor
struct ChatViewModelTests {
    private struct Harness {
        let repository: InMemoryChatRepository
        let provider: FakeChatProvider
        let subscription: FakeSubscriptionService
        let service: ChatService
        let model: ChatViewModel
        let copied: Locked<[String]>
    }

    private func makeHarness(
        isPremium: Bool = true,
        script: FakeChatProvider.Script = .reply("Hello"),
        chatId: UUID? = nil,
        prompt: String? = nil,
        repository: InMemoryChatRepository = InMemoryChatRepository(),
        copySucceeds: Bool = true
    ) -> Harness {
        let provider = FakeChatProvider(script: script)
        let subscription = FakeSubscriptionService(isPremium: isPremium)
        let service = ChatService(repository: repository, provider: provider,
                                  connectivity: FakeConnectivityMonitor(isOnline: true))
        let copied = Locked<[String]>([])
        let model = ChatViewModel(chatId: chatId, prompt: prompt, repository: repository, session: service,
                                  subscription: subscription,
                                  copyToPasteboard: { text in
                                      copied.withLock { $0.append(text) }
                                      return copySucceeds
                                  },
                                  now: { Date(timeIntervalSinceReferenceDate: 0) })
        return Harness(repository: repository, provider: provider, subscription: subscription, service: service,
                       model: model, copied: copied)
    }

    /// Пока экран «жив» — наблюдает за базой для текущего `chatId` (как `.task(id:)` во View).
    private func observing(_ model: ChatViewModel) -> Task<Void, Never> {
        Task {
            var observed: UUID?
            while !Task.isCancelled {
                if model.chatId != observed, model.chatId != nil {
                    observed = model.chatId
                    Task { await model.observe() }
                }
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    @Test func newChatSendCreatesChatAndShowsReply() async throws {
        let harness = makeHarness(prompt: "Hi!")
        let observation = observing(harness.model)
        defer { observation.cancel() }
        #expect(harness.model.isEmpty)
        #expect(harness.model.draft == "Hi!")

        await harness.model.send()

        #expect(harness.model.draft.isEmpty)
        let chatId = try #require(harness.model.chatId)
        try await waitUntil { harness.model.messages.map(\.text) == ["Hi!", "Hello"] }
        #expect(harness.model.chat?.id == chatId)
        #expect(!harness.model.isGenerating)
    }

    /// Без подписки — пейвол, текст остаётся, запроса нет.
    @Test func freeUserSendOpensPaywallAndKeepsPrompt() async {
        let harness = makeHarness(isPremium: false)
        var paywalls = 0
        harness.model.onPaywall = { paywalls += 1 }
        harness.model.draft = "Write a short email"

        await harness.model.send()

        #expect(paywalls == 1)
        #expect(harness.model.draft == "Write a short email")
        #expect(harness.model.chatId == nil)
        #expect(harness.provider.requests.isEmpty)
    }

    /// После покупки тот же текст уходит без перезапуска.
    @Test func sendWorksRightAfterPurchase() async throws {
        let harness = makeHarness(isPremium: false)
        harness.model.draft = "Question"
        await harness.model.send()

        harness.subscription.setPremium(true)
        await harness.model.send()

        try await waitUntil { harness.provider.requests.count == 1 }
        #expect(harness.model.draft.isEmpty)
    }

    @Test func sendIsDisabledWhileGeneratingAndForBlankText() async throws {
        let harness = makeHarness(script: .hang)
        let observation = observing(harness.model)
        defer { observation.cancel() }
        harness.model.draft = "   \n"
        #expect(!harness.model.canSend)

        harness.model.draft = "First"
        await harness.model.send()
        try await waitUntil { harness.model.isGenerating }
        harness.model.draft = "Second"

        #expect(!harness.model.canSend)
        try await harness.service.deleteChat(id: try #require(harness.model.chatId))
    }

    @Test func suggestionFillsDraftWithoutSending() {
        let harness = makeHarness()
        harness.model.useSuggestion(ChatViewModel.suggestions[3])
        #expect(harness.model.draft == "Plan my day")
        #expect(harness.provider.requests.isEmpty)
    }

    @Test func copyShowsToast() {
        let ok = makeHarness()
        let message = Message(chatId: UUID(), role: .assistant, text: "Answer", status: .done, createdAt: .now)
        ok.model.copy(message)
        #expect(ok.copied.withLock { $0 } == ["Answer"])
        #expect(ok.model.toast?.kind == .success)

        let failing = makeHarness(copySucceeds: false)
        failing.model.copy(message)
        #expect(failing.model.toast?.kind == .failure)
    }

    @Test func onlyLastAnswerCanBeRegenerated() async throws {
        let harness = makeHarness(script: .reply("Ok"))
        let observation = observing(harness.model)
        defer { observation.cancel() }
        harness.model.draft = "One"
        await harness.model.send()
        try await waitUntil { harness.model.messages.last?.status == .done }
        harness.model.draft = "Two"
        await harness.model.send()
        try await waitUntil { harness.model.messages.count == 4 && harness.model.messages.last?.status == .done }

        let answers = harness.model.messages.filter { $0.role == .assistant }
        #expect(!harness.model.canRegenerate(answers[0]))
        #expect(harness.model.canRegenerate(answers[1]))
    }

    @Test func retryFailedAnswer() async throws {
        let harness = makeHarness(script: .fail(APIError(kind: .server)))
        let observation = observing(harness.model)
        defer { observation.cancel() }
        harness.model.draft = "Question"
        await harness.model.send()
        try await waitUntil { harness.model.messages.last?.status == .failed }
        try await waitUntil { !harness.service.isGenerating(chatId: harness.model.chatId ?? UUID()) }
        harness.provider.setScript(.reply("Fixed"))

        await harness.model.retry(try #require(harness.model.messages.last))

        try await waitUntil { harness.model.messages.last?.text == "Fixed" }
    }
}
