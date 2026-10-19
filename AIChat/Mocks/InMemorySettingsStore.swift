#if DEBUG
import Combine
import Foundation

/// Настройки в памяти — для превью и тестов.
@MainActor
final class InMemorySettingsStore: SettingsStoring, ObservableObject {
    @Published var hasCompletedOnboarding: Bool
    @Published var notifyOnReply: Bool
    @Published var notifyOnQueuedSent: Bool

    init(hasCompletedOnboarding: Bool = false, notifyOnReply: Bool = false, notifyOnQueuedSent: Bool = false) {
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.notifyOnReply = notifyOnReply
        self.notifyOnQueuedSent = notifyOnQueuedSent
    }
}
#endif
