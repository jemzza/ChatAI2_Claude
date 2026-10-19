import Foundation
import Testing
@testable import AIChat

@MainActor
private final class RecordingPhotoSaver: PhotoSaving {
    var saved: [URL] = []
    var error: Error?

    func saveVideo(at fileURL: URL) async throws {
        if let error { throw error }
        saved.append(fileURL)
    }
}

@MainActor
struct GenerationViewModelTests {
    private struct Harness {
        let repository: InMemoryVideoRepository
        let media: FakeMediaStore
        let saver: RecordingPhotoSaver
        let model: GenerationViewModel
    }

    private func makeHarness(_ generation: VideoGeneration, replaceResult: Result<UUID, Error> = .success(UUID()))
        -> Harness {
        let repository = InMemoryVideoRepository([generation])
        let media = FakeMediaStore()
        let saver = RecordingPhotoSaver()
        let service = VideoGenerationService(repository: repository, api: FakeVideoAPI(), media: media,
                                             connectivity: FakeConnectivityMonitor(isOnline: false))
        let model = GenerationViewModel(id: generation.id, repository: repository, media: media, photoSaver: saver,
                                        service: service) { _, _ in try replaceResult.get() }
        return Harness(repository: repository, media: media, saver: saver, model: model)
    }

    private func generation(status: VideoGenerationStatus, local: String? = nil,
                            remote: URL? = URL(string: "https://media.example.test/v.mp4")) -> VideoGeneration {
        VideoGeneration(templateId: 1, templateName: "Clay Fool", aspect: .square, quality: .p720,
                        sourceImageName: "p.jpg", status: status, serverId: 1, videoURL: remote,
                        localVideoName: local, createdAt: Date(timeIntervalSinceReferenceDate: 0))
    }

    @Test func phaseFollowsGenerationStatus() {
        let media = FakeMediaStore()
        #expect(GenerationViewModel.phase(for: nil, media: media) == .missing)
        #expect(GenerationViewModel.phase(for: generation(status: .generating), media: media) == .generating)
        #expect(GenerationViewModel.phase(for: generation(status: .creating), media: media) == .generating)
        #expect(GenerationViewModel.phase(for: generation(status: .succeeded, local: "a.mp4"), media: media)
                == .ready(media.videoURL(named: "a.mp4")))
        #expect(GenerationViewModel.phase(for: generation(status: .succeeded), media: media)
                == .ready(URL(string: "https://media.example.test/v.mp4")!))
        var failed = generation(status: .failed)
        failed.failure = MessageFailure(kind: .paymentRequired)
        #expect(GenerationViewModel.phase(for: failed, media: media) == .failed(.paymentRequired))
    }

    /// Открыли готовый результат — бейдж «New» в истории снимается.
    @Test func readyResultIsMarkedViewed() async throws {
        let harness = makeHarness(generation(status: .succeeded, local: "a.mp4"))
        let task = Task { await harness.model.observe() }
        defer { task.cancel() }

        try await waitUntil { harness.model.generation?.isViewed == true }
    }

    @Test func saveDownloadsMissingFileThenSaves() async throws {
        let harness = makeHarness(generation(status: .succeeded))
        let task = Task { await harness.model.observe() }
        defer { task.cancel() }
        try await waitUntil { harness.model.generation != nil }

        await harness.model.save()

        #expect(harness.media.downloads == [URL(string: "https://media.example.test/v.mp4")!])
        #expect(harness.saver.saved.count == 1)
        #expect(harness.model.saveResult == .saved)
    }

    @Test func saveFailureShowsError() async throws {
        let harness = makeHarness(generation(status: .succeeded))
        harness.saver.error = SystemPhotoSaver.AccessDenied()
        let task = Task { await harness.model.observe() }
        defer { task.cancel() }
        try await waitUntil { harness.model.generation != nil }

        await harness.model.save()

        #expect(harness.model.saveResult == .failed)
    }

    @Test func replaceOpensNewGeneration() async throws {
        let newId = UUID()
        let harness = makeHarness(generation(status: .succeeded), replaceResult: .success(newId))
        var opened: [UUID] = []
        harness.model.onReplaced = { opened.append($0) }
        let task = Task { await harness.model.observe() }
        defer { task.cancel() }
        try await waitUntil { harness.model.generation != nil }

        await harness.model.replacePhoto(Data([1]))

        #expect(opened == [newId])
    }
}
