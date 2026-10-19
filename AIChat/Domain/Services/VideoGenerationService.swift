import Foundation

/// Генерация видео: фото → `template2video` → опрос статуса → скачивание результата.
///
/// - Всё состояние — в `VideoRepository`; экраны (генерация, результат, история) читают базу.
/// - Задачами владеет сервис (живёт в `AppContainer`): уход с экрана генерацию не отменяет,
///   после перезапуска, появления сети и возврата в приложение незавершённые продолжаются.
@MainActor
final class VideoGenerationService {
    struct Configuration: Sendable {
        /// Паузы между опросами статуса; последняя повторяется.
        var pollIntervals: [Duration] = [.seconds(3), .seconds(5), .seconds(10)]
        /// Сколько опросов ждать, прежде чем считать генерацию неудачной (~15 минут).
        var maxPolls = 90
    }

    enum CreateError: Error, Hashable {
        /// Фото не прочиталось или не сохранилось — «Upload failed».
        case invalidPhoto
    }

    private let repository: any VideoRepository
    private let api: any VideoAPI
    private let media: any MediaStoring
    private let connectivity: any ConnectivityMonitoring
    private let backgroundTasks: (any BackgroundTaskScheduling)?
    private let eventHandler: (any VideoEventHandling)?
    private let configuration: Configuration
    private let sleep: @Sendable (Duration) async throws -> Void
    private let now: () -> Date

    /// Генерации, которые сейчас ведёт сервис. `token` — чтобы закончившаяся старая задача
    /// не сняла с учёта новую (после «Try again»).
    private var tasks: [UUID: (token: UUID, task: Task<Void, Never>)] = [:]

    init(
        repository: any VideoRepository,
        api: any VideoAPI,
        media: any MediaStoring,
        connectivity: any ConnectivityMonitoring,
        backgroundTasks: (any BackgroundTaskScheduling)? = nil,
        eventHandler: (any VideoEventHandling)? = nil,
        configuration: Configuration = Configuration(),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        now: @escaping () -> Date = Date.init
    ) {
        self.repository = repository
        self.api = api
        self.media = media
        self.connectivity = connectivity
        self.backgroundTasks = backgroundTasks
        self.eventHandler = eventHandler
        self.configuration = configuration
        self.sleep = sleep
        self.now = now
    }

    func isRunning(id: UUID) -> Bool {
        tasks[id] != nil
    }

    // MARK: Жизненный цикл приложения

    /// Пока жива задача вызывающего: запуск и каждое появление сети продолжают незавершённые.
    func run() async {
        for await isOnline in connectivity.updates() where isOnline {
            await resume()
        }
    }

    /// Возврат в foreground — ещё один повод продолжить.
    func appDidBecomeActive() {
        Task { await resume() }
    }

    /// Запускает опрос для всех `creating`/`generating`, которые сервис ещё не ведёт.
    func resume() async {
        guard connectivity.isOnline, let active = try? await repository.activeGenerations() else { return }
        for generation in active where tasks[generation.id] == nil {
            start(generation.id)
        }
    }

    // MARK: Действия экранов

    /// Сохраняет фото, создаёт генерацию и запускает её. - Returns: id генерации.
    /// - Throws: `CreateError.invalidPhoto`; ошибки базы.
    func create(template: VideoTemplate, photo: Data, aspect: VideoAspect, quality: VideoQuality) async throws -> UUID {
        guard let imageName = await media.saveSourceImage(photo, aspect: aspect) else {
            throw CreateError.invalidPhoto
        }
        let generation = VideoGeneration(templateId: template.id, templateName: template.name, aspect: aspect,
                                         quality: quality, sourceImageName: imageName, createdAt: now())
        do {
            try await repository.insert(generation)
        } catch {
            media.deleteFiles(sourceImageName: imageName, videoName: nil)
            throw error
        }
        start(generation.id)
        return generation.id
    }

    /// «Try again» у ошибки: та же фотография и параметры, новая серверная генерация.
    func retry(id: UUID) async throws {
        var generation = try await repository.generation(id: id)
        guard generation.status == .failed, tasks[id] == nil else { return }
        generation.status = .creating
        generation.serverId = nil
        generation.videoURL = nil
        generation.failure = nil
        try await repository.update(generation)
        start(id)
    }

    /// Результат открыт — бейдж «New» больше не нужен.
    func markViewed(id: UUID) async {
        guard var generation = try? await repository.generation(id: id), !generation.isViewed else { return }
        generation.isViewed = true
        try? await repository.update(generation)
    }

    func delete(id: UUID) async throws {
        tasks[id]?.task.cancel()
        tasks[id] = nil
        let generation = try? await repository.generation(id: id)
        try await repository.delete(id: id)
        media.deleteFiles(sourceImageName: generation?.sourceImageName, videoName: generation?.localVideoName)
    }

    // MARK: Генерация

    private func start(_ id: UUID) {
        guard tasks[id] == nil else { return }
        let token = UUID()
        let task = Task { [weak self] in
            await self?.process(id)
            if self?.tasks[id]?.token == token { self?.tasks[id] = nil }
        }
        tasks[id] = (token, task)
    }

    private func process(_ id: UUID) async {
        let backgroundToken = backgroundTasks?.beginTask { [weak self] in
            // Время кончилось — бросаем опрос; статус в базе остаётся, продолжим при возврате.
            self?.tasks[id]?.task.cancel()
        }
        defer {
            if let backgroundToken { backgroundTasks?.endTask(backgroundToken) }
        }
        do {
            var generation = try await repository.generation(id: id)
            if generation.status == .creating {
                generation = try await submit(generation)
            }
            if generation.status == .generating {
                generation = try await poll(generation)
            }
            if generation.status == .succeeded {
                await download(generation)
                await eventHandler?.videoDidFinish(generationId: id, templateName: generation.templateName)
            }
        } catch is CancellationError {
            // Удалено, отменено системой — состояние в базе продолжит `resume()`.
        } catch let error as APIError where error.kind == .offline {
            // Нет сети — генерация остаётся активной, продолжит `run()`, когда сеть появится.
        } catch is VideoGenerationNotFound {
            // Удалили, пока шёл запрос.
        } catch {
            await markFailed(id, error: error)
        }
    }

    private func submit(_ generation: VideoGeneration) async throws -> VideoGeneration {
        guard let image = media.sourceImage(named: generation.sourceImageName) else {
            throw APIError(kind: .unknown)
        }
        // Длительность не передаём — сервер берёт её из настроек шаблона.
        let serverId = try await api.createVideo(templateId: generation.templateId, imageJPEG: image,
                                                 quality: generation.quality, duration: nil)
        var updated = try await repository.generation(id: generation.id)
        updated.serverId = serverId
        updated.status = .generating
        try await repository.update(updated)
        return updated
    }

    private func poll(_ generation: VideoGeneration) async throws -> VideoGeneration {
        guard let serverId = generation.serverId else { throw APIError(kind: .unknown) }
        for attempt in 0..<configuration.maxPolls {
            switch try await api.status(serverId: serverId) {
            case let .succeeded(url):
                var updated = try await repository.generation(id: generation.id)
                updated.status = .succeeded
                updated.videoURL = url
                try await repository.update(updated)
                return updated
            case .failed:
                throw APIError(kind: .server)
            case .generating:
                let intervals = configuration.pollIntervals
                try await sleep(intervals[min(attempt, intervals.count - 1)])
            }
        }
        throw APIError(kind: .server)
    }

    /// Результат — в кэш; не скачалось — проиграем по ссылке, это не ошибка генерации.
    private func download(_ generation: VideoGeneration) async {
        guard generation.localVideoName == nil, let url = generation.videoURL,
              let name = try? await media.downloadVideo(from: url)
        else { return }
        guard var updated = try? await repository.generation(id: generation.id) else {
            media.deleteFiles(sourceImageName: nil, videoName: name)
            return
        }
        updated.localVideoName = name
        try? await repository.update(updated)
    }

    private func markFailed(_ id: UUID, error: any Error) async {
        guard var generation = try? await repository.generation(id: id) else { return }
        let kind = (error as? APIError)?.kind ?? .unknown
        // 404 у статуса — сервер генерацию потерял: для пользователя это та же ошибка генерации.
        generation.failure = MessageFailure(kind: kind == .notFound ? .server : kind)
        generation.status = .failed
        try? await repository.update(generation)
    }
}
