import Foundation

/// Чат. В хранилище появляется только вместе с первым сообщением;
/// «New chat» до отправки — черновик во ViewModel.
struct Chat: Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    let createdAt: Date
    /// Время последнего сообщения — обновляет репозиторий.
    var updatedAt: Date
    /// Папка; `nil` — чат в «Recents».
    var folderId: UUID? = nil
    /// Когда закреплён; `nil` — не закреплён. Закреплённые — в секции «Pinned» истории.
    var pinnedAt: Date? = nil
}
