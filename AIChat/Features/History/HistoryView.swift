import SwiftUI
import UIKit

/// История (макеты «History — …»): переключатель Chat | Video, шапка и переключатель
/// закреплены, прокручивается только список.
struct HistoryView: View {
    @StateObject private var model: HistoryViewModel
    @EnvironmentObject private var router: AppRouter
    private let thumbnails: any VideoThumbnailing
    private let media: any MediaStoring

    @State private var renaming: ChatSummary?
    @State private var newTitle = ""
    @State private var deleting: ChatSummary?
    /// Папки: свёрнутые, диалоги создания/переименования/удаления, перенос чата.
    @State private var collapsedFolders: Set<UUID> = []
    @State private var isCreatingFolder = false
    @State private var renamingFolder: Folder?
    @State private var deletingFolder: Folder?
    @State private var folderName = ""
    @State private var moving: ChatSummary?
    /// Чат, который положить в создаваемую папку (из «Move → New folder…»).
    @State private var chatForNewFolder: ChatSummary?

    init(tab: HistoryTab, dependencies: AppDependencies) {
        thumbnails = dependencies.thumbnails
        media = dependencies.media
        _model = StateObject(wrappedValue: HistoryViewModel(
            tab: tab, chatRepository: dependencies.repository, session: dependencies.chat,
            videoRepository: dependencies.videoRepository, video: dependencies.video
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            NavigationHeader("History") { router.pop() }
            SegmentedTabs(selection: $model.tab)
                .padding(.horizontal, AppMetrics.sideInset)
                .padding(.vertical, 8)
            Group {
                switch model.tab {
                case .chat: chats
                case .video: videos
                }
            }
            .frame(maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.2), value: model.tab)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .task { await model.observe() }
        .alert("Rename chat", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Chat name", text: $newTitle)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let chat = renaming { Task { await model.rename(chat.id, to: newTitle) } }
            }
            .disabled(!HistoryViewModel.canRename(to: newTitle))
        } message: {
            Text("Enter a new name for this chat")
        }
        .alert("New folder", isPresented: $isCreatingFolder) {
            TextField("Folder name", text: $folderName)
            Button("Cancel", role: .cancel) { chatForNewFolder = nil }
            Button("Create") {
                let name = folderName
                let chat = chatForNewFolder
                chatForNewFolder = nil
                Task { await model.createFolder(named: name, moving: chat?.id) }
            }
            .disabled(!HistoryViewModel.canRename(to: folderName))
        }
        .alert("Rename folder", isPresented: Binding(get: { renamingFolder != nil },
                                                     set: { if !$0 { renamingFolder = nil } })) {
            TextField("Folder name", text: $folderName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let folder = renamingFolder { Task { await model.renameFolder(folder.id, to: folderName) } }
            }
            .disabled(!HistoryViewModel.canRename(to: folderName))
        }
        .alert("Delete folder?", isPresented: Binding(get: { deletingFolder != nil },
                                                      set: { if !$0 { deletingFolder = nil } })) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let folder = deletingFolder { Task { await model.deleteFolder(folder.id) } }
            }
        } message: {
            Text("Chats from this folder will stay in your history.")
        }
        .confirmationDialog("Move to folder", isPresented: Binding(get: { moving != nil },
                                                                   set: { if !$0 { moving = nil } }),
                            titleVisibility: .visible, presenting: moving) { chat in
            ForEach(model.allFolders.filter { $0.id != chat.chat.folderId }) { folder in
                // Название папки — данные пользователя.
                Button(folder.name) { Task { await model.move(chat.id, toFolder: folder.id) } }
            }
            if chat.chat.folderId != nil {
                Button("Remove from folder") { Task { await model.move(chat.id, toFolder: nil) } }
            }
            Button("New folder…") {
                chatForNewFolder = chat
                folderName = ""
                isCreatingFolder = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete chat?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let chat = deleting { Task { await model.delete(chat.id) } }
            }
        } message: {
            Text("This chat will be removed from your history.")
        }
    }

    // MARK: Чаты

    @ViewBuilder
    private var chats: some View {
        if model.isChatsEmpty {
            EmptyHistoryView(icon: "IconMagicPencil", title: "No chats yet",
                             subtitle: "Start a conversation to see\nyour history here")
        } else {
            // Системный List — ради надёжных свайп-действий (свой жест в ScrollView конфликтует с прокруткой).
            List {
                if !model.pinned.isEmpty {
                    chatSection(Text("Pinned"), chats: model.pinned)
                }
                foldersSection
                ForEach(model.sections) { section in
                    chatSection(title(for: section.group), chats: section.chats)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
            .animation(.easeInOut(duration: 0.25), value: model.sections)
            .animation(.easeInOut(duration: 0.25), value: model.pinned)
            .animation(.easeInOut(duration: 0.25), value: model.folders)
            .animation(.easeInOut(duration: 0.25), value: collapsedFolders)
        }
    }

    /// «Folders»: папки с их чатами; «+» — новая папка (решение заказчика: папки — в истории).
    private var foldersSection: some View {
        Section {
            ForEach(model.folders) { section in
                FolderRow(folder: section.folder, count: section.chats.count,
                          isExpanded: !collapsedFolders.contains(section.id)) {
                    if collapsedFolders.contains(section.id) {
                        collapsedFolders.remove(section.id)
                    } else {
                        collapsedFolders.insert(section.id)
                    }
                }
                .contextMenu {
                    Button {
                        folderName = section.folder.name
                        renamingFolder = section.folder
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        deletingFolder = section.folder
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .modifier(HistoryRowStyle())
                if !collapsedFolders.contains(section.id) {
                    ForEach(section.chats) { summary in
                        chatRow(summary)
                            .padding(.leading, 24)
                    }
                }
            }
        } header: {
            HStack {
                sectionTitle(Text("Folders"))
                Spacer()
                Button {
                    chatForNewFolder = nil
                    folderName = ""
                    isCreatingFolder = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppGradient.primary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(Text("New folder"))
            }
            .padding(.trailing, 4)
            .listRowInsets(EdgeInsets())
            .background(Color.appBackground)
        }
    }

    private func chatSection(_ title: Text, chats: [ChatSummary]) -> some View {
        Section {
            ForEach(chats) { summary in
                chatRow(summary)
            }
        } header: {
            sectionTitle(title)
                .background(Color.appBackground)
        }
    }

    private func sectionTitle(_ title: Text) -> some View {
        title
            .font(AppFont.title3)
            .foregroundStyle(Color.appAccent)
            .textCase(nil)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppMetrics.sideInset)
            .listRowInsets(EdgeInsets())
            .accessibilityAddTraits(.isHeader)
    }

    private func chatRow(_ summary: ChatSummary) -> some View {
        Button {
                    router.push(.chat(chatId: summary.id, prompt: nil))
                } label: {
                    ChatHistoryRow(summary: summary)
                }
                .buttonStyle(PressableButtonStyle())
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        deleting = summary
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(.red)
                    Button {
                        newTitle = summary.chat.title
                        renaming = summary
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .tint(.orange)
                    Button {
                        moving = summary
                    } label: {
                        Label("Move", systemImage: "folder")
                    }
                    .tint(.appGradientStart)
                }
                .modifier(HistoryRowStyle())
    }

    private func title(for group: HistoryViewModel.DateGroup) -> Text {
        switch group {
        case .today: Text("Today")
        case .yesterday: Text("Yesterday")
        case let .day(date):
            // «March 4»; другой год — «March 4, 2025».
            Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
                ? Text(date.formatted(.dateTime.month(.wide).day()))
                : Text(date.formatted(.dateTime.month(.wide).day().year()))
        }
    }

    // MARK: Видео

    @ViewBuilder
    private var videos: some View {
        if model.isVideosEmpty {
            EmptyHistoryView(icon: "IconImageToImage", title: "No videos yet",
                             subtitle: "Create your first video to see it here")
        } else {
            GeometryReader { proxy in
            ScrollView {
                MasonryGrid(items: model.videos, width: proxy.size.width - AppMetrics.sideInset * 2,
                            spacing: 8) { generation in
                    VideoHistoryCard(generation: generation, thumbnails: thumbnails, media: media) {
                        router.push(.generation(id: generation.id))
                    } onRetry: {
                        Task { await model.retry(generation.id) }
                    }
                } height: { generation, width in
                    width / generation.aspect.ratio
                }
                .padding(.horizontal, AppMetrics.sideInset)
                .padding(.top, 24)
                .padding(.bottom, 16)
                .animation(.easeInOut(duration: 0.25), value: model.videos)
            }
            }
        }
    }
}

// MARK: - Компоненты истории

/// Переключатель Chat | Video: выбранный сегмент — подложка 8% белого.
private struct SegmentedTabs: View {
    @Binding var selection: HistoryTab
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 0) {
            segment(.chat, title: "Chat")
            segment(.video, title: "Video")
        }
        .padding(4)
        .frame(height: 40)
        .background(Color.appSurface.opacity(0.4), in: Capsule())
    }

    private func segment(_ tab: HistoryTab, title: LocalizedStringKey) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { selection = tab }
        } label: {
            Text(title)
                .font(AppFont.headline)
                .foregroundStyle(Color.appAccent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    if selection == tab {
                        Capsule().fill(Color.appFillTertiary)
                            .matchedGeometryEffect(id: "segment", in: namespace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
    }
}

/// Строка чата: иконка, название, превью последнего сообщения, булавка у закреплённых.
private struct ChatHistoryRow: View {
    let summary: ChatSummary

    var body: some View {
        HStack(spacing: 16) {
            Image("IconGenerate")
                .resizable()
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                // Название и текст сообщения — данные пользователя.
                Text(summary.chat.title)
                    .font(AppFont.headline)
                    .foregroundStyle(Color.appAccent)
                if let last = summary.lastMessage {
                    Text(last.replacingOccurrences(of: "\n", with: " "))
                        .font(AppFont.subheadline)
                        .foregroundStyle(Color.appAccent.opacity(0.5))
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            if summary.chat.pinnedAt != nil {
                Image(systemName: "pin")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.appAccent.opacity(0.3))
                    .accessibilityLabel(Text("Pinned"))
            }
        }
        .padding(16)
        .background(Color.appSurface.opacity(0.4), in: RoundedRectangle(cornerRadius: AppMetrics.cardRadius))
        .contentShape(RoundedRectangle(cornerRadius: AppMetrics.cardRadius))
    }
}

/// Строка списка истории без фона и разделителей, с отступами макета.
private struct HistoryRowStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets(top: 6, leading: AppMetrics.sideInset, bottom: 6, trailing: AppMetrics.sideInset))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

/// Папка: иконка, название, число чатов, стрелка раскрытия.
private struct FolderRow: View {
    let folder: Folder
    let count: Int
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 16) {
                Image(systemName: "folder")
                    .font(.system(size: 20))
                    .foregroundStyle(AppGradient.primary)
                    .frame(width: 28, height: 28)
                // Название папки — данные пользователя.
                Text(folder.name)
                    .font(AppFont.headline)
                    .foregroundStyle(Color.appAccent)
                    .lineLimit(1)
                Spacer()
                Text("\(count)")
                    .font(AppFont.subheadline)
                    .foregroundStyle(Color.appAccent.opacity(0.5))
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.appAccent.opacity(0.5))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .padding(16)
            .background(Color.appSurface.opacity(0.4), in: RoundedRectangle(cornerRadius: AppMetrics.cardRadius))
            .contentShape(RoundedRectangle(cornerRadius: AppMetrics.cardRadius))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityValue(Text(isExpanded ? "Expanded" : "Collapsed"))
    }
}

/// Пустое состояние вкладки.
private struct EmptyHistoryView: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(spacing: 16) {
            Image(icon)
                .resizable()
                .frame(width: 60, height: 60)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text(title)
                    .font(AppFont.title)
                    .tracking(0.4)
                Text(subtitle)
                    .font(AppFont.body)
                    .opacity(0.5)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(Color.appAccent)
        }
        .padding(.horizontal, AppMetrics.sideInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: -40)
    }
}

/// Две колонки: каждая следующая карточка — в более короткую колонку (masonry из макета).
private struct MasonryGrid<Item: Identifiable, Cell: View>: View {
    let items: [Item]
    /// Ширина всей сетки — снаружи: в ScrollView своей ширины заранее не узнать.
    let width: CGFloat
    let spacing: CGFloat
    @ViewBuilder let cell: (Item) -> Cell
    let height: (Item, CGFloat) -> CGFloat

    var body: some View {
        let columnWidth = max((width - spacing) / 2, 0)
        let columns = split(columnWidth: columnWidth)
        HStack(alignment: .top, spacing: spacing) {
            ForEach(0..<2, id: \.self) { column in
                LazyVStack(spacing: spacing) {
                    ForEach(columns[column]) { item in
                        cell(item).frame(height: height(item, columnWidth))
                    }
                }
                .frame(width: columnWidth)
            }
        }
    }

    private func split(columnWidth: CGFloat) -> [[Item]] {
        var columns: [[Item]] = [[], []]
        var heights: [CGFloat] = [0, 0]
        for item in items {
            let column = heights[0] <= heights[1] ? 0 : 1
            columns[column].append(item)
            heights[column] += height(item, columnWidth) + spacing
        }
        return columns
    }
}

/// Карточка видео в истории: результат, «In progress» (размытое фото + спиннер),
/// «New» до первого открытия, «Error» с «Try again».
private struct VideoHistoryCard: View {
    let generation: VideoGeneration
    let thumbnails: any VideoThumbnailing
    let media: any MediaStoring
    let onOpen: () -> Void
    let onRetry: () -> Void

    var body: some View {
        Button(action: onOpen) {
            ZStack {
                background
                overlay
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(alignment: .topLeading) { badge.padding(8) }
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(PressableButtonStyle())
    }

    @ViewBuilder
    private var background: some View {
        switch generation.status {
        case .succeeded:
            VideoThumbnailView(url: resultURL, thumbnails: thumbnails)
        case .creating, .generating, .failed:
            LocalImageView(url: media.sourceImageURL(named: generation.sourceImageName))
                .blur(radius: 6)
                .overlay(Color.appBackground.opacity(0.55))
        }
    }

    @ViewBuilder
    private var overlay: some View {
        switch generation.status {
        case .creating, .generating:
            VStack(spacing: 8) {
                ProgressView().tint(.appAccent).controlSize(.regular)
                Text("Generating…")
                    .font(.custom("Inter-Medium", size: 13, relativeTo: .footnote))
                    .foregroundStyle(Color.appAccent.opacity(0.85))
            }
        case .failed:
            VStack(spacing: 8) {
                Text("Something went wrong")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.appAccent.opacity(0.85))
                    .multilineTextAlignment(.center)
                Button(action: onRetry) {
                    Text("Try again")
                        .font(AppFont.captionMedium)
                        .foregroundStyle(Color.appAccent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.15), in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
            }
            .padding(8)
        case .succeeded:
            EmptyView()
        }
    }

    @ViewBuilder
    private var badge: some View {
        switch generation.status {
        case .creating, .generating:
            StatusBadge(title: "In progress", color: .appGradientStart)
        case .failed:
            StatusBadge(title: "Error", color: .red)
        case .succeeded:
            if !generation.isViewed {
                StatusBadge(title: "New", color: .green)
            }
        }
    }

    private var resultURL: URL? {
        generation.localVideoName.map { media.videoURL(named: $0) } ?? generation.videoURL
    }
}

/// Бейдж статуса: точка и подпись на тёмной капсуле с обводкой цвета статуса.
private struct StatusBadge: View {
    let title: LocalizedStringKey
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title)
                .font(AppFont.captionMedium)
                .foregroundStyle(color)
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
        .background(Color.appBackground.opacity(0.7), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.5)))
    }
}

/// Картинка из локального файла (исходное фото генерации), декодируется вне главного потока.
private struct LocalImageView: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.appSurface
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            }
        }
        .clipped()
        .task(id: url) {
            image = await Task.detached(priority: .utility) {
                (try? Data(contentsOf: url)).flatMap { ImageDownscaler.jpeg(from: $0) }.flatMap(UIImage.init(data:))
            }.value
        }
    }
}
