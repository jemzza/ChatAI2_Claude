#if DEBUG
import Foundation

/// `VideoRepository` в памяти — для превью и тестов.
final class InMemoryVideoRepository: VideoRepository {
    private struct State {
        /// Порядок вставки — для одинаковых `createdAt`.
        var generations: [UUID: (generation: VideoGeneration, order: Int)] = [:]
        var nextOrder = 0
        var listObservers: [UUID: AsyncStream<[VideoGeneration]>.Continuation] = [:]
        var itemObservers: [UUID: (id: UUID, continuation: AsyncStream<VideoGeneration?>.Continuation)] = [:]

        var newestFirst: [VideoGeneration] {
            generations.values
                .sorted { ($0.generation.createdAt, $0.order) > ($1.generation.createdAt, $1.order) }
                .map(\.generation)
        }

        func notify() {
            let list = newestFirst
            for continuation in listObservers.values { continuation.yield(list) }
            for observer in itemObservers.values {
                observer.continuation.yield(generations[observer.id]?.generation)
            }
        }
    }

    private let state = Locked(State())

    init(_ generations: [VideoGeneration] = []) {
        state.withLock { state in
            for generation in generations {
                state.generations[generation.id] = (generation, state.nextOrder)
                state.nextOrder += 1
            }
        }
    }

    func observeGenerations() -> AsyncStream<[VideoGeneration]> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let id = UUID()
            state.withLock { state in
                state.listObservers[id] = continuation
                continuation.yield(state.newestFirst)
            }
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { _ = $0.listObservers.removeValue(forKey: id) }
            }
        }
    }

    func observeGeneration(id: UUID) -> AsyncStream<VideoGeneration?> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let observerId = UUID()
            state.withLock { state in
                state.itemObservers[observerId] = (id, continuation)
                continuation.yield(state.generations[id]?.generation)
            }
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { _ = $0.itemObservers.removeValue(forKey: observerId) }
            }
        }
    }

    func insert(_ generation: VideoGeneration) {
        state.withLock { state in
            state.generations[generation.id] = (generation, state.nextOrder)
            state.nextOrder += 1
            state.notify()
        }
    }

    func update(_ generation: VideoGeneration) throws {
        try state.withLock { state in
            guard let stored = state.generations[generation.id] else {
                throw VideoGenerationNotFound(id: generation.id)
            }
            state.generations[generation.id] = (generation, stored.order)
            state.notify()
        }
    }

    func generation(id: UUID) throws -> VideoGeneration {
        guard let generation = state.withLock({ $0.generations[id]?.generation }) else {
            throw VideoGenerationNotFound(id: id)
        }
        return generation
    }

    func delete(id: UUID) {
        state.withLock { state in
            guard state.generations.removeValue(forKey: id) != nil else { return }
            state.notify()
        }
    }

    func activeGenerations() -> [VideoGeneration] {
        state.withLock { state in
            state.generations.values
                .filter { $0.generation.status.isActive }
                .sorted { ($0.generation.createdAt, $0.order) < ($1.generation.createdAt, $1.order) }
                .map(\.generation)
        }
    }
}
#endif
