import Foundation
import Testing
@testable import AIChat

@MainActor
struct SettingsViewModelTests {
    private func makeModel(status: NotificationAuthorization = .notDetermined, grants: Bool = true,
                           enabled: Bool = false, subscription: FakeSubscriptionService = FakeSubscriptionService())
        -> (SettingsViewModel, InMemorySettingsStore, FakeNotificationScheduler) {
        let settings = InMemorySettingsStore(notifyOnReply: enabled)
        let scheduler = FakeNotificationScheduler(status: status, grantsOnRequest: grants)
        let model = SettingsViewModel(settings: settings, scheduler: scheduler, cache: FakeCacheManager(),
                                      subscription: subscription)
        return (model, settings, scheduler)
    }

    @Test func enablingAsksPermissionOnce() async {
        let (model, settings, scheduler) = makeModel()

        await model.toggleNotifications(true)

        #expect(model.notificationsEnabled)
        #expect(settings.notifyOnReply)
        #expect(scheduler.requestCount == 1)
    }

    @Test func refusedPermissionKeepsToggleOff() async {
        let (model, settings, _) = makeModel(grants: false)
        await model.toggleNotifications(true)
        #expect(!model.notificationsEnabled)
        #expect(!settings.notifyOnReply)
    }

    @Test func deniedInSystemShowsAlert() async {
        let (model, _, scheduler) = makeModel(status: .denied)
        await model.toggleNotifications(true)
        #expect(!model.notificationsEnabled)
        #expect(model.alert == .notificationsDenied)
        #expect(scheduler.requestCount == 0)
    }

    @Test func revokedPermissionTurnsToggleOffOnLoad() async {
        let (model, settings, _) = makeModel(status: .denied, enabled: true)
        await model.load()
        #expect(!model.notificationsEnabled)
        #expect(!settings.notifyOnReply)
    }

    @Test func clearCacheResetsSize() async {
        let (model, _, _) = makeModel()
        await model.load()
        #expect(model.cacheSize == 5_000_000)
        await model.clearCache()
        #expect(model.cacheSize == 0)
    }

    @Test func restoreOutcomes() async {
        let restored = FakeSubscriptionService()
        let (ok, _, _) = makeModel(subscription: restored)
        await ok.restore()
        #expect(ok.alert == .restored)
        #expect(restored.isPremium)

        let nothing = FakeSubscriptionService()
        nothing.restoreResult = .success(false)
        let (empty, _, _) = makeModel(subscription: nothing)
        await empty.restore()
        #expect(empty.alert == .nothingToRestore)

        let failing = FakeSubscriptionService()
        failing.restoreResult = .failure(.restoreFailed)
        let (failed, _, _) = makeModel(subscription: failing)
        await failed.restore()
        #expect(failed.alert == .restoreFailed)
    }
}
