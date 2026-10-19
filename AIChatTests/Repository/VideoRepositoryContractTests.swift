import Foundation
import Testing
@testable import AIChat

enum VideoRepositoryKind: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case inMemory
    case grdb

    func make() -> any VideoRepository {
        switch self {
        case .inMemory: InMemoryVideoRepository()
        case .grdb: GRDBVideoRepository(database: try! AppDatabase.inMemory())
        }
    }

    var testDescription: String { rawValue }
}

private let t0 = Date(timeIntervalSinceReferenceDate: 700_000_000.25)

private func makeGeneration(at seconds: TimeInterval = 0, status: VideoGenerationStatus = .creating) -> VideoGeneration {
    VideoGeneration(templateId: 374_743_997_109_542, templateName: "Dense Snowflakes", aspect: .portrait,
                    quality: .p720, sourceImageName: "\(UUID().uuidString).jpg", status: status,
                    createdAt: t0.addingTimeInterval(seconds))
}

/// Одни и те же проверки для GRDB и in-memory: фейк ведёт себя как настоящая база.
struct VideoRepositoryContractTests {
    @Test(arguments: VideoRepositoryKind.allCases)
    func insertedGenerationsComeNewestFirst(kind: VideoRepositoryKind) async throws {
        let repository = kind.make()
        let old = makeGeneration(at: 0)
        let new = makeGeneration(at: 10)

        try await repository.insert(old)
        try await repository.insert(new)

        let list = try await firstValue(of: repository.observeGenerations()) { $0.count == 2 }
        #expect(list.map(\.id) == [new.id, old.id])
        #expect(list.last == old)
    }

    @Test(arguments: VideoRepositoryKind.allCases)
    func updateRoundTripsEveryField(kind: VideoRepositoryKind) async throws {
        let repository = kind.make()
        var generation = makeGeneration()
        try await repository.insert(generation)

        generation.status = .failed
        generation.serverId = 900_001
        generation.videoURL = URL(string: "https://media.pixverse.ai/pixverse%2Fmp4%2Fseed0.mp4")
        generation.localVideoName = "video.mp4"
        generation.failure = MessageFailure(kind: .paymentRequired, retryAt: t0.addingTimeInterval(30))
        generation.isViewed = true
        try await repository.update(generation)

        #expect(try await repository.generation(id: generation.id) == generation)
        let observed = try await firstValue(of: repository.observeGeneration(id: generation.id)) { $0?.isViewed == true }
        #expect(observed == generation)
    }

    @Test(arguments: VideoRepositoryKind.allCases)
    func missingGenerationThrowsOnUpdateAndRead(kind: VideoRepositoryKind) async {
        let repository = kind.make()
        let generation = makeGeneration()
        await #expect(throws: VideoGenerationNotFound(id: generation.id)) {
            try await repository.update(generation)
        }
        await #expect(throws: VideoGenerationNotFound(id: generation.id)) {
            _ = try await repository.generation(id: generation.id)
        }
    }

    @Test(arguments: VideoRepositoryKind.allCases)
    func deleteIsIdempotentAndObservedAsNil(kind: VideoRepositoryKind) async throws {
        let repository = kind.make()
        let generation = makeGeneration()
        try await repository.insert(generation)

        try await repository.delete(id: generation.id)
        try await repository.delete(id: generation.id)

        #expect(try await firstValue(of: repository.observeGeneration(id: generation.id)) { $0 == nil } == nil)
        #expect(try await firstValue(of: repository.observeGenerations()).isEmpty)
    }

    @Test(arguments: VideoRepositoryKind.allCases)
    func activeGenerationsAreOldestFirst(kind: VideoRepositoryKind) async throws {
        let repository = kind.make()
        let creating = makeGeneration(at: 5, status: .creating)
        let generating = makeGeneration(at: 1, status: .generating)
        for generation in [creating, generating, makeGeneration(at: 2, status: .succeeded),
                           makeGeneration(at: 3, status: .failed)] {
            try await repository.insert(generation)
        }

        #expect(try await repository.activeGenerations().map(\.id) == [generating.id, creating.id])
    }
}
