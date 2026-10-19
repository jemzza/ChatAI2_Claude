import Foundation
import Testing
@testable import AIChat

@MainActor
struct BroadcastTests {
    @Test func emitsCurrentValueThenOnlyChanges() async {
        let broadcast = Broadcast(false)
        var iterator = broadcast.updates().makeAsyncIterator()

        #expect(await iterator.next() == false)
        broadcast.set(false)  // без изменения — не шлём
        broadcast.set(true)
        #expect(await iterator.next() == true)
    }

    @Test func everySubscriberGetsUpdates() async {
        let broadcast = Broadcast(0)
        var first = broadcast.updates().makeAsyncIterator()
        var second = broadcast.updates().makeAsyncIterator()
        _ = await first.next()
        _ = await second.next()

        broadcast.set(5)

        #expect(await first.next() == 5)
        #expect(await second.next() == 5)
    }
}

@MainActor
struct FakeSubscriptionServiceTests {
    /// Покупка в другом месте приложения сразу видна подписчику — без перезапуска.
    @Test func premiumChangeReachesSubscriberImmediately() async {
        let service = FakeSubscriptionService(isPremium: false)
        var updates = service.premiumUpdates().makeAsyncIterator()
        #expect(await updates.next() == false)

        service.setPremium(true)

        #expect(await updates.next() == true)
        #expect(service.isPremium)
    }
}
