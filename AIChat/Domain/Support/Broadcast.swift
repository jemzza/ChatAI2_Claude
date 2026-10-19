import Foundation

/// Значение, на изменения которого можно подписаться несколько раз:
/// каждый `updates()` — свой поток, текущее значение сразу, дальше только изменения.
@MainActor
final class Broadcast<Value: Equatable & Sendable> {
    private(set) var value: Value
    private var observers: [UUID: AsyncStream<Value>.Continuation] = [:]

    init(_ value: Value) {
        self.value = value
    }

    func set(_ newValue: Value) {
        guard newValue != value else { return }
        value = newValue
        for continuation in observers.values { continuation.yield(newValue) }
    }

    func updates() -> AsyncStream<Value> {
        AsyncStream { continuation in
            let id = UUID()
            observers[id] = continuation
            continuation.yield(value)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.observers.removeValue(forKey: id) }
            }
        }
    }
}
