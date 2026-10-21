import Foundation

/// Экран генерации и результата (макеты «AI Video — Generating / Result …»).
/// Состояние — из базы: пока генерируется — анимация, готово — плеер, ошибка — «Try again».
/// Уход с экрана генерацию не отменяет (ею владеет `VideoGenerationService`).
@MainActor
final class GenerationViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case generating
        case ready(URL)
        case failed(ErrorKind)
        /// Генерацию удалили (например, из истории).
        case missing
    }

    /// Карточка поверх результата (заметки «Save Success / Save Error»).
    enum SaveResult: Equatable {
        case saved
        case failed
    }

    typealias Replace = @MainActor (VideoGeneration, Data) async throws -> UUID

    @Published private(set) var generation: VideoGeneration?
    @Published private(set) var phase = Phase.loading
    @Published var isPlaying = false
    @Published private(set) var isSaving = false
    @Published var saveResult: SaveResult?
    /// Файл для системного share sheet; `nil` — закрыт.
    @Published var shareURL: URL?
    @Published var toast: ToastMessage?

    let id: UUID
    private let repository: any VideoRepository
    private let media: any MediaStoring
    private let photoSaver: any PhotoSaving
    private let service: VideoGenerationService
    private let replace: Replace
    /// Новая генерация после «Replace» — экран переключается на неё.
    var onReplaced: (UUID) -> Void = { _ in }

    init(id: UUID, repository: any VideoRepository, media: any MediaStoring, photoSaver: any PhotoSaving,
         service: VideoGenerationService, replace: @escaping Replace) {
        self.id = id
        self.repository = repository
        self.media = media
        self.photoSaver = photoSaver
        self.service = service
        self.replace = replace
    }

    var aspect: VideoAspect { generation?.aspect ?? .portrait }

    func observe() async {
        for await generation in repository.observeGeneration(id: id) {
            self.generation = generation
            let newPhase = Self.phase(for: generation, media: media)
            if newPhase != phase { phase = newPhase }
            if case .ready = newPhase, generation?.isViewed == false {
                await service.markViewed(id: id)
            }
        }
    }

    static func phase(for generation: VideoGeneration?, media: any MediaStoring) -> Phase {
        guard let generation else { return .missing }
        switch generation.status {
        case .creating, .generating:
            return .generating
        case .failed:
            return .failed(generation.failure?.kind ?? .unknown)
        case .succeeded:
            // Кэш могли очистить («Clear cache») — тогда играем по ссылке.
            if let local = generation.localVideoName.flatMap(media.localVideoURL(named:)) { return .ready(local) }
            if let url = generation.videoURL { return .ready(url) }
            return .failed(.unknown)
        }
    }

    func togglePlayback() {
        isPlaying.toggle()
    }

    func retry() async {
        try? await service.retry(id: id)
    }

    /// «Download» — в «Фото». Нет файла в кэше — сначала скачиваем.
    func save() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await photoSaver.saveVideo(at: try await localFile())
            saveResult = .saved
        } catch {
            saveResult = .failed
        }
    }

    func share() async {
        do {
            shareURL = try await localFile()
        } catch {
            toast = ToastMessage(kind: .failure, text: "Couldn't load video")
        }
    }

    /// «Replace»: то же шаблон и параметры, новое фото → новая генерация.
    func replacePhoto(_ data: Data) async {
        guard let generation else { return }
        do {
            onReplaced(try await replace(generation, data))
        } catch {
            toast = ToastMessage(kind: .failure, text: "Upload failed")
        }
    }

    private func localFile() async throws -> URL {
        guard let generation else { throw APIError(kind: .notFound) }
        if let local = generation.localVideoName.flatMap(media.localVideoURL(named:)) { return local }
        guard let remote = generation.videoURL else { throw APIError(kind: .notFound) }
        return media.videoURL(named: try await media.downloadVideo(from: remote))
    }
}
