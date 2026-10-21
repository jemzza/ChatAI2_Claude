import Foundation

/// Настройки (макет «Settings»): уведомления, кэш, восстановление покупок.
@MainActor
final class SettingsViewModel: ObservableObject {
    enum Alert: Identifiable, Equatable {
        /// Уведомления запрещены в системе — предложить открыть Настройки.
        case notificationsDenied
        case restored
        case nothingToRestore
        case restoreFailed

        var id: Self { self }
    }

    @Published private(set) var notificationsEnabled: Bool
    @Published private(set) var cacheSize: Int64?
    @Published private(set) var isRestoring = false
    @Published var alert: Alert?

    private let settings: any SettingsStoring
    private let scheduler: any LocalNotificationScheduling
    private let cache: any CacheManaging
    private let subscription: any SubscriptionService

    init(settings: any SettingsStoring, scheduler: any LocalNotificationScheduling, cache: any CacheManaging,
         subscription: any SubscriptionService) {
        self.settings = settings
        self.scheduler = scheduler
        self.cache = cache
        self.subscription = subscription
        notificationsEnabled = settings.notifyOnReply
    }

    func load() async {
        cacheSize = await cache.size()
        // Разрешение отозвали в системе — переключатель не должен врать.
        if notificationsEnabled, await scheduler.authorization() == .denied {
            setNotifications(false)
        }
    }

    /// Включение спрашивает разрешение (первый раз — системный запрос; запрещено — алерт).
    func toggleNotifications(_ isOn: Bool) async {
        guard isOn else {
            setNotifications(false)
            return
        }
        switch await scheduler.authorization() {
        case .authorized:
            setNotifications(true)
        case .notDetermined:
            setNotifications(await scheduler.requestAuthorization())
        case .denied:
            setNotifications(false)
            alert = .notificationsDenied
        }
    }

    func clearCache() async {
        await cache.clear()
        cacheSize = await cache.size()
    }

    func restore() async {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }
        do {
            alert = try await subscription.restore() ? .restored : .nothingToRestore
        } catch {
            alert = .restoreFailed
        }
    }

    private func setNotifications(_ isOn: Bool) {
        notificationsEnabled = isOn
        // Один переключатель в макете — и ответы чата, и готовые видео.
        settings.notifyOnReply = isOn
        settings.notifyOnQueuedSent = isOn
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
}
