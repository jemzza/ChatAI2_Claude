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

    struct ChatSection: Identifiable, Hashable {
        let group: DateGroup
        let chats: [ChatSummary]
        var id: DateGroup { group }
    }

    @Published var tab: HistoryTab
    @Published private(set) var pinned: [ChatSummary] = []
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

    var isChatsEmpty: Bool { hasLoadedChats && pinned.isEmpty && sections.isEmpty }
    var isVideosEmpty: Bool { hasLoadedVideos && videos.isEmpty }

    func observe() async {
        async let chats: Void = observeChats()
        async let videos: Void = observeVideos()
        _ = await (chats, videos)
    }

    private func observeChats() async {
        for await summaries in chatRepository.observeChatSummaries() {
            apply(summaries)
            hasLoadedChats = true
        }
    }

    private func observeVideos() async {
        for await generations in videoRepository.observeGenerations() {
            videos = generations
            hasLoadedVideos = true
        }
    }

    func apply(_ summaries: [ChatSummary]) {
        pinned = summaries
            .filter { $0.chat.pinnedAt != nil }
            .sorted { ($0.chat.pinnedAt ?? .distantPast) > ($1.chat.pinnedAt ?? .distantPast) }
        var sections: [ChatSection] = []
        for summary in summaries where summary.chat.pinnedAt == nil {
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

    // MARK: Видео

    func retry(_ generationId: UUID) async {
        try? await video.retry(id: generationId)
    }
}
