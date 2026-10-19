import Foundation
@testable import AIChat

/// Репозиторий-обёртка: всё передаёт дальше и запоминает вызовы `updateMessage`.
final class RecordingRepository: ChatRepository {
    let base: any ChatRepository
    private let updates = Locked<[MessageStatus]>([])

    init(base: any ChatRepository) {
        self.base = base
    }

    var updateStatuses: [MessageStatus] { updates.withLock { $0 } }

    func observeChats() -> AsyncStream<[Chat]> { base.observeChats() }
    func observeMessages(chatId: UUID) -> AsyncStream<[Message]> { base.observeMessages(chatId: chatId) }
    func insertChat(_ chat: Chat, firstMessage: Message) async throws {
        try await base.insertChat(chat, firstMessage: firstMessage)
    }
    func renameChat(id: UUID, title: String) async throws { try await base.renameChat(id: id, title: title) }
    func setPinned(chatId: UUID, at pinnedAt: Date?) async throws {
        try await base.setPinned(chatId: chatId, at: pinnedAt)
    }
    func deleteChat(id: UUID) async throws { try await base.deleteChat(id: id) }
    func deleteAll() async throws { try await base.deleteAll() }
    func observeSidebar() -> AsyncStream<SidebarSnapshot> { base.observeSidebar() }
    func moveChat(id: UUID, toFolder folderId: UUID?) async throws {
        try await base.moveChat(id: id, toFolder: folderId)
    }
    func createFolder(id: UUID, name: String, createdAt: Date) async throws {
        try await base.createFolder(id: id, name: name, createdAt: createdAt)
    }
    func renameFolder(id: UUID, name: String) async throws { try await base.renameFolder(id: id, name: name) }
    func deleteFolder(id: UUID) async throws { try await base.deleteFolder(id: id) }
    func moveFolder(id: UUID, to index: Int) async throws { try await base.moveFolder(id: id, to: index) }
    func insertMessage(_ message: Message) async throws { try await base.insertMessage(message) }
    func updateMessage(id: UUID, text: String, status: MessageStatus, failure: MessageFailure?) async throws {
        updates.withLock { $0.append(status) }
        try await base.updateMessage(id: id, text: text, status: status, failure: failure)
    }
    func history(chatId: UUID, before messageId: UUID, limit: Int) async throws -> [Message] {
        try await base.history(chatId: chatId, before: messageId, limit: limit)
    }
    func pendingMessages() async throws -> [Message] { try await base.pendingMessages() }
    func claimPending(messageId: UUID, reply: Message) async throws -> Bool {
        try await base.claimPending(messageId: messageId, reply: reply)
    }
    func claimRetry(assistantMessageId: UUID) async throws -> Bool {
        try await base.claimRetry(assistantMessageId: assistantMessageId)
    }
    func markGeneratingAsInterrupted() async throws -> Int { try await base.markGeneratingAsInterrupted() }
}

/// Фоновые задачи под контролем теста: можно «забрать время» у генерации.
@MainActor
final class ManualBackgroundTasks: BackgroundTaskScheduling {
    private var expirations: [Int: @MainActor () -> Void] = [:]
    private var nextToken = 1
    private(set) var endedTokens: [Int] = []

    var activeCount: Int { expirations.count }

    func beginTask(expiration: @escaping @MainActor () -> Void) -> Int {
        defer { nextToken += 1 }
        expirations[nextToken] = expiration
        return nextToken
    }

    func endTask(_ token: Int) {
        expirations[token] = nil
        endedTokens.append(token)
    }

    func expireAll() {
        for expiration in expirations.values { expiration() }
    }
}

/// Время, которое идёт вперёд на секунду при каждом вызове: у сообщений разные `createdAt`.
@MainActor
final class SteppingDates {
    private var current: Date

    init(start: Date) {
        current = start
    }

    func next() -> Date {
        current = current.addingTimeInterval(1)
        return current
    }
}
