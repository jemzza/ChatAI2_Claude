import Foundation

/// Шаблон видео из каталога PixVerse.
struct VideoTemplate: Identifiable, Hashable, Sendable {
    /// `template_id` — его отправляем в `template2video`.
    let id: Int64
    let name: String
    /// Категория с эмодзи, как в API: «📈 Trending».
    let category: String
    /// Превью-ролик (mp4).
    let previewURL: URL?
    /// Доступные качества; пусто — любое из `VideoQuality`.
    let qualities: [VideoQuality]
    /// Длительность в секундах.
    let duration: Int?
}

/// Соотношение сторон результата (выбор «Format» в макете).
enum VideoAspect: String, CaseIterable, Hashable, Sendable {
    case landscape = "16:9"
    case portrait = "9:16"
    case square = "1:1"

    /// Ширина к высоте.
    var ratio: Double {
        switch self {
        case .landscape: 16.0 / 9.0
        case .portrait: 9.0 / 16.0
        case .square: 1
        }
    }
}

/// Качество генерации — значения API.
enum VideoQuality: String, CaseIterable, Hashable, Sendable {
    case p360 = "360p"
    case p540 = "540p"
    case p720 = "720p"
    case p1080 = "1080p"
}

enum VideoGenerationStatus: String, Hashable, Sendable {
    /// Запрос на создание ещё не принят сервером (нет `serverId`).
    case creating
    /// Сервер генерирует — опрашиваем статус.
    case generating
    case succeeded
    case failed

    var isActive: Bool { self == .creating || self == .generating }
}

/// Генерация видео. Хранится в базе: история, фоновое продолжение, «Try again».
struct VideoGeneration: Identifiable, Hashable, Sendable {
    let id: UUID
    let templateId: Int64
    let templateName: String
    let aspect: VideoAspect
    let quality: VideoQuality
    /// Исходное фото (уже обрезанное под формат) — имя файла в хранилище фото.
    let sourceImageName: String
    var status: VideoGenerationStatus
    /// `video_id` из ответа `template2video`.
    var serverId: Int64?
    /// Ссылка на результат.
    var videoURL: URL?
    /// Скачанный результат — имя файла в кэше видео.
    var localVideoName: String?
    var failure: MessageFailure?
    /// Пользователь открыл результат — бейдж «New» больше не показываем.
    var isViewed: Bool
    let createdAt: Date

    init(
        id: UUID = UUID(),
        templateId: Int64,
        templateName: String,
        aspect: VideoAspect,
        quality: VideoQuality,
        sourceImageName: String,
        status: VideoGenerationStatus = .creating,
        serverId: Int64? = nil,
        videoURL: URL? = nil,
        localVideoName: String? = nil,
        failure: MessageFailure? = nil,
        isViewed: Bool = false,
        createdAt: Date
    ) {
        self.id = id
        self.templateId = templateId
        self.templateName = templateName
        self.aspect = aspect
        self.quality = quality
        self.sourceImageName = sourceImageName
        self.status = status
        self.serverId = serverId
        self.videoURL = videoURL
        self.localVideoName = localVideoName
        self.failure = failure
        self.isViewed = isViewed
        self.createdAt = createdAt
    }
}

struct VideoGenerationNotFound: Error, Hashable, Sendable {
    let id: UUID
}
