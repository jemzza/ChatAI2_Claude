import Foundation
import Testing
@testable import AIChat

@MainActor
struct AppContainerTests {
    @Test func detectsUnitTestHost() {
        #expect(AppContainer.environment(for: .processInfo) == .unitTests)
    }

    @Test func keepsGivenEnvironment() {
        #expect(AppContainer(environment: .live).environment == .live)
    }

    /// Без launch-аргументов фейки не подключаются.
    @Test func usesRealImplementationsByDefault() {
        #expect(AppContainer(environment: .live).launchOptions == .none)
        #expect(AppContainer(environment: .live).launchOptions.usesMocks == false)
    }
}

struct LaunchOptionsTests {
    @Test func noArgumentsMeansNoMocks() {
        #expect(LaunchOptions(arguments: []) == .none)
        #expect(LaunchOptions(arguments: ["/path/AIChat", "-NSDoubleLocalizedStrings", "YES"]).usesMocks == false)
    }

    /// Так приложение реально запускается в этом процессе — фейков быть не должно.
    @Test func currentProcessArgumentsDoNotEnableMocks() {
        #expect(LaunchOptions(arguments: ProcessInfo.processInfo.arguments).usesMocks == false)
    }

    @Test func parsesEachFlag() {
        let options = LaunchOptions(arguments: ["app", "-mockData", "-mockOffline", "-mockSlowReply"])
        #expect(options.useMockData)
        #expect(options.forceOffline)
        #expect(options.slowReply)
        #expect(options.mockError == nil)
        #expect(options.usesMocks)
    }

    @Test(arguments: [
        ("429", ErrorKind.rateLimited), ("401", .unauthorized), ("403", .forbidden),
        ("500", .server), ("offline", .offline), ("teapot", .unknown),
    ])
    func parsesMockError(value: String, kind: ErrorKind) {
        #expect(LaunchOptions(arguments: ["app", "-mockError", value]).mockError == kind)
    }

    @Test func mockErrorWithoutValueIsUnknown() {
        #expect(LaunchOptions(arguments: ["app", "-mockError"]).mockError == .unknown)
    }
}

struct DependencyPlanTests {
    /// Обычный запуск — только реальные реализации.
    @Test func defaultsToRealImplementations() {
        let plan = DependencyPlan(options: .none)
        #expect(plan.storage == .disk)
        #expect(plan.network == .system)
        #expect(plan.model == .live)
    }

    @Test func eachFlagSwitchesOnlyItsPart() {
        #expect(DependencyPlan(options: LaunchOptions(arguments: ["app", "-mockData"]))
                == DependencyPlan(storage: .previewData, network: .system, model: .live))
        #expect(DependencyPlan(options: LaunchOptions(arguments: ["app", "-mockOffline"]))
                == DependencyPlan(storage: .disk, network: .offline, model: .live))
        #expect(DependencyPlan(options: LaunchOptions(arguments: ["app", "-mockSlowReply"]))
                == DependencyPlan(storage: .disk, network: .system, model: .slowReply))
        #expect(DependencyPlan(options: LaunchOptions(arguments: ["app", "-mockError", "429"]))
                == DependencyPlan(storage: .disk, network: .system, model: .failing(.rateLimited)))
    }

    @Test func subscriptionFlagsSwitchOnlySubscription() {
        #expect(DependencyPlan(options: .none).subscription == .apphud)
        #expect(DependencyPlan(options: LaunchOptions(arguments: ["app", "-mockPremium"]))
                == DependencyPlan(storage: .disk, network: .system, model: .live, subscription: .fake(isPremium: true)))
        #expect(DependencyPlan(options: LaunchOptions(arguments: ["app", "-mockFree"])).subscription
                == .fake(isPremium: false))
        // Оба флага — побеждает `-mockPremium`.
        #expect(LaunchOptions(arguments: ["app", "-mockFree", "-mockPremium"]).mockPremium == true)
    }

    /// Ошибка важнее медленного ответа: сценарий ошибки проверяем независимо.
    @Test func mockErrorWinsOverSlowStream() {
        let options = LaunchOptions(arguments: ["app", "-mockSlowReply", "-mockError", "403"])
        #expect(DependencyPlan(options: options).model == .failing(.forbidden))
    }
}

