import Foundation
import Testing
@testable import AIChat

@MainActor
struct SettingsStoreTests {
    /// Отдельный набор `UserDefaults` на каждый тест — не трогаем настройки приложения.
    private let suiteName = "SettingsStoreTests.\(UUID().uuidString)"

    private func makeDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: suiteName))
    }

    @Test func defaultsKeepNotificationsOff() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsSettingsStore(defaults: defaults)

        #expect(store.notifyOnReply == false)
        #expect(store.notifyOnQueuedSent == false)
        #expect(store.hasCompletedOnboarding == false)
    }

    @Test func changesSurviveNewInstance() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsSettingsStore(defaults: defaults)
        store.notifyOnReply = true
        store.hasCompletedOnboarding = true
        store.notifyOnQueuedSent = true

        let reloaded = UserDefaultsSettingsStore(defaults: defaults)
        #expect(reloaded.notifyOnReply == true)
        #expect(reloaded.hasCompletedOnboarding == true)
        #expect(reloaded.notifyOnQueuedSent == true)

        reloaded.notifyOnReply = false
        let again = UserDefaultsSettingsStore(defaults: defaults)
        #expect(again.notifyOnReply == false)
    }
}
