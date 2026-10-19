#if DEBUG
import Combine
import Foundation

/// Настройки в памяти — для превью и тестов.
@MainActor
final class InMemorySettingsStore: SettingsStoring, ObservableObject {
    @Published var notifyOnReply: Bool
    @Published var notifyOnQueuedSent: Bool

    init(notifyOnReply: Bool = false, notifyOnQueuedSent: Bool = false) {
        self.notifyOnReply = notifyOnReply
        self.notifyOnQueuedSent = notifyOnQueuedSent
    }
}
#endif
