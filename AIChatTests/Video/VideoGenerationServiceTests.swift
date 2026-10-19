import Foundation
import Testing
@testable import AIChat

@MainActor
private final class RecordingVideoEvents: VideoEventHandling {
    private(set) var finished: [UUID] = []

    func videoDidFinish(generationId: UUID, templateName: String) async {
        finished.append(generationId)
    }
}

@MainActor
struct VideoGenerationServiceTests {
    private struct Harness {
        let repository: InMemoryVideoRepository
        let api: FakeVideoAPI
        let media: FakeMediaStore
        let connectivity: FakeConnectivityMonitor
        let backgroundTasks: ManualBackgroundTasks
        let events: RecordingVideoEvents
        let service: VideoGenerationService
    }

    private let template = FakeVideoAPI.sampleTemplates[0]
    private let photo = Data([0xFF, 0xD8, 0x01])

    private func makeHarness(
        statuses: [Result<VideoServerStatus, APIError>] = [.success(.succeeded(FakeVideoAPI.sampleVideoURL))],
        isOnline: Bool = true,
        repository: InMemoryVideoRepository = InMemoryVideoRepository(),
        maxPolls: Int = 90
    ) -> Harness {
        let api = FakeVideoAPI(statuses: statuses)
        let media = FakeMediaStore()
        let connectivity = FakeConnectivityMonitor(isOnline: isOnline)
        let backgroundTasks = ManualBackgroundTasks()
        let events = RecordingVideoEvents()
        let service = VideoGenerationService(
            repository: repository, api: api, media: media, connectivity: connectivity,
            backgroundTasks: backgroundTasks, eventHandler: events,
            configuration: .init(pollIntervals: [.zero], maxPolls: maxPolls),
            sleep: { _ in await Task.yield() },
            now: { Date(timeIntervalSinceReferenceDate: 1000) }
        )
        return Harness(repository: repository, api: api, media: media, connectivity: connectivity,
                       backgroundTasks: backgroundTasks, events: events, service: service)
    }

    private func generation(_ harness: Harness, _ id: UUID,
                            where predicate: @escaping @Sendable (VideoGeneration?) -> Bool) async throws -> VideoGeneration? {
        try await firstValue(of: harness.repository.observeGeneration(id: id), where: predicate)
    }

    // MARK: Создание и опрос

    @Test func createPollsUntilSuccessAndDownloads() async throws {
        let harness = makeHarness(statuses: [.success(.generating), .success(.generating),
                                             .success(.succeeded(FakeVideoAPI.sampleVideoURL))])

        let id = try await harness.service.create(template: template, photo: photo, aspect: .portrait, quality: .p1080)

        let done = try #require(try await generation(harness, id) { $0?.localVideoName != nil })
        #expect(done.status == .succeeded)
        #expect(done.serverId == 900_001)
        #expect(done.videoURL == FakeVideoAPI.sampleVideoURL)
        #expect(done.aspect == .portrait)
        #expect(done.isViewed == false)
        #expect(harness.api.creates == [FakeVideoAPI.Create(templateId: template.id, imageJPEG: photo, quality: .p1080)])
        #expect(harness.api.statusRequests == 3)
        try await waitUntil { !harness.service.isRunning(id: id) }
        #expect(harness.events.finished == [id])
        #expect(harness.backgroundTasks.activeCount == 0)
    }

    @Test func invalidPhotoFailsBeforeAnyRequest() async {
        let harness = makeHarness()
        await #expect(throws: VideoGenerationService.CreateError.invalidPhoto) {
            _ = try await harness.service.create(template: template, photo: Data(), aspect: .square, quality: .p720)
        }
        #expect(harness.api.creates.isEmpty)
        #expect(harness.repository.activeGenerations().isEmpty)
    }

    @Test(arguments: [
        (Result<VideoServerStatus, APIError>.success(.failed), ErrorKind.server),
        (.failure(APIError(kind: .notFound)), .server),
        (.failure(APIError(kind: .paymentRequired)), .paymentRequired),
    ])
    func serverFailureMarksFailed(status: Result<VideoServerStatus, APIError>, kind: ErrorKind) async throws {
        let harness = makeHarness(statuses: [status])

        let id = try await harness.service.create(template: template, photo: photo, aspect: .square, quality: .p720)

        let failed = try await generation(harness, id) { $0?.status == .failed }
        #expect(failed?.failure?.kind == kind)
        #expect(harness.events.finished.isEmpty)
    }

    @Test func createErrorMarksFailed() async throws {
        let harness = makeHarness()
        harness.api.setCreateResult(.failure(APIError(kind: .paymentRequired)))

        let id = try await harness.service.create(template: template, photo: photo, aspect: .square, quality: .p720)

        let failed = try await generation(harness, id) { $0?.status == .failed }
        #expect(failed?.failure?.kind == .paymentRequired)
        #expect(failed?.serverId == nil)
    }

    @Test func pollingGivesUpAfterLimit() async throws {
        let harness = makeHarness(statuses: [.success(.generating)], maxPolls: 3)

        let id = try await harness.service.create(template: template, photo: photo, aspect: .square, quality: .p720)

        _ = try await generation(harness, id) { $0?.status == .failed }
        #expect(harness.api.statusRequests == 3)
    }

    /// Скачать не удалось — генерация всё равно готова, проиграем по ссылке.
    @Test func failedDownloadKeepsRemoteResult() async throws {
        let harness = makeHarness()
        harness.media.setDownloadResult(.failure(APIError(kind: .offline)))

        let id = try await harness.service.create(template: template, photo: photo, aspect: .square, quality: .p720)

        try await waitUntil { !harness.service.isRunning(id: id) }
        let done = try await harness.repository.generation(id: id)
        #expect(done.status == .succeeded)
        #expect(done.localVideoName == nil)
        #expect(done.videoURL == FakeVideoAPI.sampleVideoURL)
    }

    // MARK: Без сети и после перезапуска

    @Test func offlineKeepsGenerationActiveAndResumesOnline() async throws {
        let harness = makeHarness()
        harness.api.setCreateResult(.failure(APIError(kind: .offline)))
        let id = try await harness.service.create(template: template, photo: photo, aspect: .square, quality: .p720)
        try await waitUntil { !harness.service.isRunning(id: id) }
        #expect(try await harness.repository.generation(id: id).status == .creating)

        harness.api.setCreateResult(.success(900_002))
        harness.connectivity.setOnline(false)
        let run = Task { await harness.service.run() }
        defer { run.cancel() }
        harness.connectivity.setOnline(true)

        let done = try await generation(harness, id) { $0?.status == .succeeded }
        #expect(done?.serverId == 900_002)
        #expect(harness.api.creates.count == 2)
    }

    /// Процесс умер посреди опроса: после запуска — тот же `video_id`, без нового создания.
    @Test func resumeContinuesPollingWithoutRecreating() async throws {
        let stored = VideoGeneration(templateId: 1, templateName: "Clay Fool", aspect: .landscape, quality: .p720,
                                     sourceImageName: "photo.jpg", status: .generating, serverId: 777,
                                     createdAt: Date(timeIntervalSinceReferenceDate: 10))
        let harness = makeHarness(repository: InMemoryVideoRepository([stored]))

        await harness.service.resume()

        _ = try await generation(harness, stored.id) { $0?.status == .succeeded }
        #expect(harness.api.creates.isEmpty)
    }

    // MARK: Действия пользователя

    @Test func retryUsesSamePhotoAndParameters() async throws {
        let harness = makeHarness(statuses: [.success(.failed)])
        let id = try await harness.service.create(template: template, photo: photo, aspect: .landscape, quality: .p540)
        _ = try await generation(harness, id) { $0?.status == .failed }
        try await waitUntil { !harness.service.isRunning(id: id) }
        harness.api.setStatuses([.success(.succeeded(FakeVideoAPI.sampleVideoURL))])

        try await harness.service.retry(id: id)

        let done = try await generation(harness, id) { $0?.status == .succeeded }
        #expect(done?.failure == nil)
        #expect(harness.api.creates.count == 2)
        #expect(harness.api.creates.allSatisfy { $0.imageJPEG == photo && $0.quality == .p540 })
    }

    @Test func markViewedClearsNewBadge() async throws {
        let harness = makeHarness()
        let id = try await harness.service.create(template: template, photo: photo, aspect: .square, quality: .p720)
        _ = try await generation(harness, id) { $0?.status == .succeeded }

        await harness.service.markViewed(id: id)

        #expect(try await harness.repository.generation(id: id).isViewed)
    }

    @Test func deleteRemovesRowAndFiles() async throws {
        let harness = makeHarness()
        let id = try await harness.service.create(template: template, photo: photo, aspect: .square, quality: .p720)
        _ = try await generation(harness, id) { $0?.localVideoName != nil }
        try await waitUntil { !harness.service.isRunning(id: id) }

        try await harness.service.delete(id: id)

        #expect(try await generation(harness, id) { $0 == nil } == nil)
        #expect(harness.media.savedImages.isEmpty)
        #expect(harness.media.videos.isEmpty)
    }
}
