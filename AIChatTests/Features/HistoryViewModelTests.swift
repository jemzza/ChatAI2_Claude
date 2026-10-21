import Foundation
import Testing
@testable import AIChat

@MainActor
struct HistoryViewModelTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    /// «Сейчас» — 2026-03-26 12:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_774_526_400)

    private func makeModel(chats: InMemoryChatRepository = InMemoryChatRepository(),
                           videos: InMemoryVideoRepository = InMemoryVideoRepository()) -> HistoryViewModel {
        let service = ChatService(repository: chats, provider: FakeChatProvider(),
                                  connectivity: FakeConnectivityMonitor(isOnline: false))
        let video = VideoGenerationService(repository: videos, api: FakeVideoAPI(), media: FakeMediaStore(),
                                           connectivity: FakeConnectivityMonitor(isOnline: false))
        let now = now
        return HistoryViewModel(tab: .chat, chatRepository: chats, session: service, videoRepository: videos,
                                video: video, calendar: calendar, now: { now })
    }

    private func summary(_ title: String, hoursAgo: Double, pinnedAt: Date? = nil) -> ChatSummary {
        let date = now.addingTimeInterval(-hoursAgo * 3600)
        return ChatSummary(chat: Chat(id: UUID(), title: title, createdAt: date, updatedAt: date, pinnedAt: pinnedAt),
                           lastMessage: "Hi")
    }

    @Test func groupsPinnedTodayYesterdayAndOlderDays() {
        let model = makeModel()
        let pinnedOld = summary("Pinned old", hoursAgo: 100, pinnedAt: now.addingTimeInterval(-50))
        let pinnedNew = summary("Pinned new", hoursAgo: 1, pinnedAt: now)
        let today = summary("Today", hoursAgo: 2)
        let yesterday = summary("Yesterday", hoursAgo: 20)
        let older = summary("March 4", hoursAgo: 22 * 24)

        model.apply([pinnedNew, today, yesterday, pinnedOld, older])

        #expect(model.pinned.map(\.chat.title) == ["Pinned new", "Pinned old"])
        #expect(model.sections.map(\.group) == [.today, .yesterday, .day(calendar.startOfDay(for: older.chat.updatedAt))])
        #expect(model.sections.map { $0.chats.map(\.chat.title) } == [["Today"], ["Yesterday"], ["March 4"]])
    }

    @Test func emptyRenameIsRejected() {
        #expect(!HistoryViewModel.canRename(to: "   "))
        #expect(HistoryViewModel.canRename(to: "W"))
    }

    @Test func renameAndDeleteChangeRepository() async throws {
        let chat = Chat(id: UUID(), title: "Old", createdAt: now, updatedAt: now)
        let repository = InMemoryChatRepository(
            chats: [chat], messages: [Message(chatId: chat.id, role: .user, text: "Hi", status: .sent, createdAt: now)]
        )
        let model = makeModel(chats: repository)
        let task = Task { await model.observe() }
        defer { task.cancel() }
        try await waitUntil { model.hasLoadedChats && !model.sections.isEmpty }

        await model.rename(chat.id, to: "  Welcome email ")
        try await waitUntil { model.sections.first?.chats.first?.chat.title == "Welcome email" }

        await model.delete(chat.id)
        try await waitUntil { model.isChatsEmpty }
    }

    @Test func emptyStatesAfterLoad() async throws {
        let model = makeModel()
        #expect(!model.isChatsEmpty)
        let task = Task { await model.observe() }
        defer { task.cancel() }
        try await waitUntil { model.isChatsEmpty && model.isVideosEmpty }
    }

    // MARK: Папки

    @Test func foldersTakeTheirChatsOutOfDateGroups() {
        let model = makeModel()
        let work = Folder(id: UUID(), name: "Work", position: 0, createdAt: now)
        var inFolder = summary("In folder", hoursAgo: 1)
        inFolder = ChatSummary(chat: Chat(id: inFolder.chat.id, title: "In folder", createdAt: inFolder.chat.createdAt,
                                          updatedAt: inFolder.chat.updatedAt, folderId: work.id), lastMessage: nil)
        let loose = summary("Loose", hoursAgo: 2)

        model.apply([inFolder, loose], folders: [work])

        #expect(model.folders.map(\.folder.name) == ["Work"])
        #expect(model.folders.first?.chats.map(\.chat.title) == ["In folder"])
        #expect(model.sections.flatMap(\.chats).map(\.chat.title) == ["Loose"])
    }

    @Test func createMoveAndDeleteFolder() async throws {
        let chat = Chat(id: UUID(), title: "Trip", createdAt: now, updatedAt: now)
        let repository = InMemoryChatRepository(
            chats: [chat], messages: [Message(chatId: chat.id, role: .user, text: "Hi", status: .sent, createdAt: now)]
        )
        let model = makeModel(chats: repository)
        let task = Task { await model.observe() }
        defer { task.cancel() }
        try await waitUntil { model.hasLoadedChats }

        await model.createFolder(named: " Travel ")
        try await waitUntil { model.folders.map(\.folder.name) == ["Travel"] }
        let folderId = try #require(model.folders.first?.id)

        await model.move(chat.id, toFolder: folderId)
        try await waitUntil { model.folders.first?.chats.count == 1 && model.sections.isEmpty }

        await model.deleteFolder(folderId)
        try await waitUntil { model.folders.isEmpty && model.sections.first?.chats.count == 1 }
    }
}
