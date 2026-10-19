import Foundation
import GRDB

extension DatabaseWriter {
    /// Наблюдение как `AsyncStream`: первое значение — сразу после подписки, дальше — после
    /// каждой транзакции, затронувшей прочитанные таблицы (одинаковые снимки подряд отбрасываются).
    /// Ошибка чтения завершает поток. Отмена потребителя останавливает наблюдение.
    func observe<Value: Equatable & Sendable>(
        on queue: DispatchQueue,
        _ fetch: @escaping @Sendable (Database) throws -> Value
    ) -> AsyncStream<Value> {
        let observation = ValueObservation.trackingConstantRegion(fetch).removeDuplicates()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let cancellable = observation.start(
                in: self,
                scheduling: .async(onQueue: queue),
                onError: { _ in continuation.finish() },
                onChange: { continuation.yield($0) }
            )
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }
}
