import Foundation

/// Значение под замком — замена `Mutex` из Synchronization, который есть только с iOS 18.
/// Тот же API (`init(_:)`, `withLock`), поэтому подходит и для не-`Sendable` состояния
/// (например, словарей с continuation'ами).
final class Locked<State>: @unchecked Sendable {
    // @unchecked: всё обращение к `state` идёт только внутри `lock`, это и даёт потокобезопасность.
    private let lock = NSLock()
    private var state: State

    init(_ state: State) {
        self.state = state
    }

    func withLock<Result>(_ body: (inout State) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&state)
    }
}
