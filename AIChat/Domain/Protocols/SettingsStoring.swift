import Foundation

/// Настройки пользователя. Хранятся вне базы (`UserDefaults`, см. docs/task.md):
/// это предпочтения устройства, а не данные переписки.
/// Реализации — `ObservableObject`, чтобы экран настроек обновлялся сам.
@MainActor
protocol SettingsStoring: AnyObject {
    /// Онбординг пройден — дальше запуск сразу с главного экрана.
    var hasCompletedOnboarding: Bool { get set }
    /// Уведомлять о готовом ответе, пока приложение не активно.
    var notifyOnReply: Bool { get set }
    /// Уведомлять, когда outbox отправил сообщения, ждавшие сети.
    var notifyOnQueuedSent: Bool { get set }
}
