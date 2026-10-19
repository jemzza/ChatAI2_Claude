import Foundation
import Testing
@testable import AIChat

@MainActor
struct PaywallViewModelTests {
    private func makeModel(_ configure: (FakeSubscriptionService) -> Void = { _ in })
        -> (PaywallViewModel, FakeSubscriptionService) {
        let subscription = FakeSubscriptionService()
        configure(subscription)
        return (PaywallViewModel(subscription: subscription, closeButtonDelay: .milliseconds(50)), subscription)
    }

    @Test func loadsPlansAndPreselectsBestValue() async {
        let (model, subscription) = makeModel()
        #expect(model.state == .loading)

        await model.load()

        #expect(model.state == .loaded)
        #expect(model.options.map(\.id) == ["com.labs.fviu.year", "com.labs.fviu.month"])
        #expect(model.selectedPlanID == "com.labs.fviu.year")
        #expect(model.options.first?.savingsPercent == 27)
        #expect(model.options.last?.savingsPercent == nil)
        #expect(subscription.shownCount == 1)
    }

    @Test func failedLoadShowsErrorAndRetryRecovers() async {
        let (model, subscription) = makeModel { $0.plansResult = .failure(.productsUnavailable) }

        await model.load()
        #expect(model.state == .failed)
        #expect(subscription.shownCount == 0)

        subscription.plansResult = .success(FakeSubscriptionService.samplePlans)
        await model.load()
        #expect(model.state == .loaded)
    }

    @Test func purchaseUnlocksAndFinishes() async {
        let (model, subscription) = makeModel()
        await model.load()
        model.selectedPlanID = "com.labs.fviu.month"

        await model.purchase()

        #expect(subscription.purchasedPlanIDs == ["com.labs.fviu.month"])
        #expect(subscription.isPremium)
        #expect(model.isFinished)
        #expect(model.alert == nil)
        #expect(!model.isPurchasing)
    }

    @Test func cancelledPurchaseIsNotAnError() async {
        let (model, _) = makeModel { $0.purchaseResult = .success(.cancelled) }
        await model.load()

        await model.purchase()

        #expect(model.alert == nil)
        #expect(!model.isFinished)
    }

    @Test(arguments: [
        (Result<PurchaseOutcome, SubscriptionError>.failure(.purchaseFailed), PaywallViewModel.Alert.purchaseFailed),
        (.success(.pending), .purchasePending),
    ])
    func purchaseProblemsShowAlert(result: Result<PurchaseOutcome, SubscriptionError>, alert: PaywallViewModel.Alert)
        async {
        let (model, _) = makeModel { $0.purchaseResult = result }
        await model.load()

        await model.purchase()

        #expect(model.alert == alert)
        #expect(!model.isFinished)
    }

    @Test func restoreOutcomes() async {
        let (restored, _) = makeModel()
        await restored.restore()
        #expect(restored.isFinished)

        let (nothing, _) = makeModel { $0.restoreResult = .success(false) }
        await nothing.restore()
        #expect(nothing.alert == .nothingToRestore)
        #expect(!nothing.isFinished)

        let (failed, _) = makeModel { $0.restoreResult = .failure(.restoreFailed) }
        await failed.restore()
        #expect(failed.alert == .restoreFailed)
    }

    /// Покупка пришла не через этот экран (например, restore на другом экране) — пейвол закрывается сам.
    @Test func externalPremiumChangeFinishes() async throws {
        let (model, subscription) = makeModel()
        let task = Task { await model.start() }
        defer { task.cancel() }
        try await waitUntil { model.state == .loaded }

        subscription.setPremium(true)

        try await waitUntil { model.isFinished }
    }

    @Test func closeButtonAppearsAfterDelay() async throws {
        let (model, _) = makeModel()
        let task = Task { await model.start() }
        defer { task.cancel() }

        try await waitUntil { model.state == .loaded }
        #expect(!model.isCloseButtonVisible)
        try await waitUntil { model.isCloseButtonVisible }
    }

    @Test func secondPurchaseWhileBusyIsIgnored() async throws {
        let (model, subscription) = makeModel { $0.delay = .milliseconds(100) }
        await model.load()

        async let first: Void = model.purchase()
        try await waitUntil { model.isPurchasing }
        await model.purchase()
        await model.restore()
        await first

        #expect(subscription.purchasedPlanIDs.count == 1)
    }
}
