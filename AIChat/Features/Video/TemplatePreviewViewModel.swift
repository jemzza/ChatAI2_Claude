import Foundation

/// Экран шаблона (макеты «AI Video — Template Preview … Quality Selection»): листание
/// шаблонов категории, фото, формат и качество, «Create».
@MainActor
final class TemplatePreviewViewModel: ObservableObject {
    /// Качество в UI — как в макете. В API нет 4K: отправляется 1080p (решение заказчика).
    enum QualityOption: CaseIterable, Hashable {
        case p720
        case p1080
        case p4k

        var apiQuality: VideoQuality {
            switch self {
            case .p720: .p720
            case .p1080, .p4k: .p1080
            }
        }
    }

    enum PhotoState: Equatable {
        case empty
        case loading
        case loaded(Data)
    }

    typealias CreateVideo = @MainActor (VideoTemplate, Data, VideoAspect, VideoQuality) async throws -> UUID

    @Published private(set) var templates: [VideoTemplate] = []
    @Published var currentIndex = 0
    @Published private(set) var photo = PhotoState.empty
    @Published var aspect = VideoAspect.landscape
    @Published var quality = QualityOption.p1080
    @Published private(set) var isCreating = false
    @Published var toast: ToastMessage?

    private let templateId: Int64
    private let category: String?
    private let api: any VideoAPI
    private let subscription: any SubscriptionService
    private let createVideo: CreateVideo
    var onPaywall: () -> Void = {}
    /// Генерация создана — экран генерации.
    var onCreated: (UUID) -> Void = { _ in }

    init(templateId: Int64, category: String?, api: any VideoAPI, subscription: any SubscriptionService,
         createVideo: @escaping CreateVideo) {
        self.templateId = templateId
        self.category = category
        self.api = api
        self.subscription = subscription
        self.createVideo = createVideo
    }

    var currentTemplate: VideoTemplate? {
        templates.indices.contains(currentIndex) ? templates[currentIndex] : nil
    }

    var canCreate: Bool {
        if case .loaded = photo { return currentTemplate != nil && !isCreating }
        return false
    }

    func load() async {
        guard templates.isEmpty, let all = try? await api.templates() else { return }
        let inCategory = category.map { category in all.filter { $0.category == category } } ?? all
        templates = inCategory.isEmpty ? all : inCategory
        currentIndex = templates.firstIndex { $0.id == templateId } ?? 0
    }

    /// Фото из галереи: пока читается — индикатор; не прочиталось — «Upload failed»
    /// и снова «+» (заметка к макету).
    func loadPhoto(_ load: () async throws -> Data?) async {
        photo = .loading
        do {
            guard let data = try await load(), !data.isEmpty else { throw CancellationError() }
            photo = .loaded(data)
        } catch {
            photo = .empty
            toast = ToastMessage(kind: .failure, text: "Upload failed")
        }
    }

    func removePhoto() {
        photo = .empty
    }

    func create() async {
        guard canCreate, case let .loaded(data) = photo, let template = currentTemplate else { return }
        guard subscription.isPremium else {
            onPaywall()
            return
        }
        isCreating = true
        defer { isCreating = false }
        do {
            let id = try await createVideo(template, data, aspect, quality.apiQuality)
            onCreated(id)
        } catch {
            // Фото не прочиталось/не сохранилось — «Upload failed», слот снова пустой.
            photo = .empty
            toast = ToastMessage(kind: .failure, text: "Upload failed")
        }
    }
}
