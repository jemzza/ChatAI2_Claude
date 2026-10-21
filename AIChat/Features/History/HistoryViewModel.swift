import Foundation

/// История (макеты «History — …»): чаты (Pinned + группы по дате) и видео.
/// Всё читается из базы; изменения — через репозиторий / сервисы.
@MainActor
final class HistoryViewModel: ObservableObject {
    /// Группа чатов по дате последней активности.
    enum DateGroup: Hashable {
        case today
        case yesterday
        /// Начало дня.
        case day(Date)
    }

    /// Папка с её чатами (закреплённые — только в «Pinned», без дублей).
    struct FolderSection: Identifiable, Hashable {
        let folder: Folder
        let chats: [ChatSummary]
        var id: UUID { folder.id }
    }

    struct ChatSection: Identifiable, Hashable {
        let group: DateGroup
        let chats: [ChatSummary]
        var id: DateGroup { group }
    }

    @Published var tab: HistoryTab
    @Published private(set) var pinned: [ChatSummary] = []
    @Published private(set) var folders: [FolderSection] = []
    @Published private(set) var sections: [ChatSection] = []
    @Published private(set) var videos: [VideoGeneration] = []
    @Published private(set) var hasLoadedChats = false
    @Published private(set) var hasLoadedVideos = false

    private let chatRepository: any ChatRepository
    private let session: any ChatSession
    private let videoRepository: any VideoRepository
    private let video: VideoGenerationService
    private let calendar: Calendar
    private let now: () -> Date

    init(tab: HistoryTab, chatRepository: any ChatRepository, session: any ChatSession,
         videoRepository: any VideoRepository, video: VideoGenerationService,
         calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
        self.tab = tab
        self.chatRepository = chatRepository
        self.session = session
        self.videoRepository = videoRepository
        self.video = video
        self.calendar = calendar
        self.now = now
    }

    var isChatsEmpty: Bool { hasLoadedChats && pinned.isEmpty && sections.isEmpty && folders.isEmpty }

    private var latestSummaries: [ChatSummary] = []
    private var latestFolders: [Folder] = []
    var isVideosEmpty: Bool { hasLoadedVideos && videos.isEmpty }

    func observe() async {
        async let chats: Void = observeChats()
        async let folders: Void = observeFolders()
        async let videos: Void = observeVideos()
        _ = await (chats, folders, videos)
    }

    private func observeChats() async {
        for await summaries in chatRepository.observeChatSummaries() {
            latestSummaries = summaries
            apply(summaries, folders: latestFolders)
            hasLoadedChats = true
        }
    }

    private func observeFolders() async {
        for await snapshot in chatRepository.observeSidebar() {
            latestFolders = snapshot.folders.map(\.folder)
            apply(latestSummaries, folders: latestFolders)
        }
    }

    private func observeVideos() async {
        for await generations in videoRepository.observeGenerations() {
            videos = generations
            hasLoadedVideos = true
        }
    }

    /// Раскладка: «Pinned» → папки (по `position`) → чаты без папки по датам.
    func apply(_ summaries: [ChatSummary], folders: [Folder] = []) {
        pinned = summaries
            .filter { $0.chat.pinnedAt != nil }
            .sorted { ($0.chat.pinnedAt ?? .distantPast) > ($1.chat.pinnedAt ?? .distantPast) }
        let unpinned = summaries.filter { $0.chat.pinnedAt == nil }
        let known = Set(folders.map(\.id))
        self.folders = folders.map { folder in
            FolderSection(folder: folder, chats: unpinned.filter { $0.chat.folderId == folder.id })
        }
        var sections: [ChatSection] = []
        // Чат со ссылкой на неизвестную папку — в общей ленте, а не теряется.
        for summary in unpinned where summary.chat.folderId.map({ !known.contains($0) }) ?? true {
            let group = group(for: summary.chat.updatedAt)
            if sections.last?.group == group {
                sections[sections.count - 1] = ChatSection(group: group, chats: sections[sections.count - 1].chats + [summary])
            } else {
                sections.append(ChatSection(group: group, chats: [summary]))
            }
        }
        self.sections = sections
    }

    private func group(for date: Date) -> DateGroup {
        let today = calendar.startOfDay(for: now())
        let day = calendar.startOfDay(for: date)
        if day == today { return .today }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), day == yesterday { return .yesterday }
        return .day(day)
    }

    // MARK: Действия с чатами

    /// Пустое (из пробелов) название сохранить нельзя — кнопка Save неактивна (заметка к макету).
    static func canRename(to title: String) -> Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func rename(_ chatId: UUID, to title: String) async {
        guard Self.canRename(to: title) else { return }
        try? await chatRepository.renameChat(id: chatId, title: title.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func delete(_ chatId: UUID) async {
        try? await session.deleteChat(id: chatId)
    }

    // MARK: Папки

    /// Новая папка; `moving` — сразу положить в неё чат («Move → New folder…»).
    func createFolder(named name: String, moving chatId: UUID? = nil) async {
        guard Self.canRename(to: name) else { return }
        let id = UUID()
        do {
            try await chatRepository.createFolder(id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                                  createdAt: now())
            if let chatId { try await chatRepository.moveChat(id: chatId, toFolder: id) }
        } catch {
            return
        }
    }

    func renameFolder(_ folderId: UUID, to name: String) async {
        guard Self.canRename(to: name) else { return }
        try? await chatRepository.renameFolder(id: folderId, name: name.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Удаляет папку; её чаты возвращаются в общую ленту.
    func deleteFolder(_ folderId: UUID) async {
        try? await chatRepository.deleteFolder(id: folderId)
    }

    /// `folderId == nil` — убрать из папки.
    func move(_ chatId: UUID, toFolder folderId: UUID?) async {
        try? await chatRepository.moveChat(id: chatId, toFolder: folderId)
    }

    var allFolders: [Folder] { folders.map(\.folder) }

    // MARK: Видео

    func retry(_ generationId: UUID) async {
        try? await video.retry(id: generationId)
    }
}
