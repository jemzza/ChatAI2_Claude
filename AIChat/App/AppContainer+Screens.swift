import Foundation

/// Какие реализации собрать. По умолчанию — только реальные; каждый фейк включается
/// только своим DEBUG launch-аргументом (в Release `LaunchOptions` всегда `.none`).
struct DependencyPlan: Hashable, Sendable {
    enum Storage: Hashable, Sendable {
        /// GRDB в Application Support.
        case disk
        /// `-mockData`: репозиторий в памяти с `PreviewData`.
        case previewData
    }

    enum Network: Hashable, Sendable {
        /// `NWPathMonitor`.
        case system
        /// `-mockOffline`: сети нет.
        case offline
    }

    enum Model: Hashable, Sendable {
        /// Настоящий AI-провайдер (Dola — шаг 3.2 плана).
        case live
        /// `-mockError <code>`: каждый ответ падает с этой ошибкой.
        case failing(ErrorKind)
        /// `-mockSlowStream`: медленный фейковый ответ.
        case slowStream
    }

    enum Subscription: Hashable, Sendable {
        /// Apphud.
        case apphud
        /// `-mockPremium` / `-mockFree`: фейк с заданным статусом.
        case fake(isPremium: Bool)
    }

    let storage: Storage
    let network: Network
    let model: Model
    let subscription: Subscription

    init(storage: Storage, network: Network, model: Model, subscription: Subscription = .apphud) {
        self.storage = storage
        self.network = network
        self.model = model
        self.subscription = subscription
    }

    init(options: LaunchOptions) {
        storage = options.useMockData ? .previewData : .disk
        network = options.forceOffline ? .offline : .system
        if let kind = options.mockError {
            model = .failing(kind)
        } else {
            model = options.slowStream ? .slowStream : .live
        }
        subscription = options.mockPremium.map { .fake(isPremium: $0) } ?? .apphud
    }
}

/// Зависимости, общие для всех экранов. Пока — база, сеть и подписка; сервисы чата
/// и видео подключаются в своих шагах плана.
@MainActor
struct AppDependencies {
    let repository: any ChatRepository
    let connectivity: any ConnectivityMonitoring
    let subscription: any SubscriptionService
}

extension AppContainer {
    /// Собирает зависимости экранов. Асинхронно: при запуске репозиторий переводит
    /// оборванные генерации в `interrupted` раньше, чем на базу подпишутся экраны.
    func makeDependencies() async throws -> AppDependencies {
        let plan = DependencyPlan(options: launchOptions)
        // Подписка — первой: её `userID` нужен каждому запросу к API.
        let subscription = makeSubscription(plan.subscription)
        return AppDependencies(
            repository: try await makeRepository(plan.storage),
            connectivity: makeConnectivity(plan.network),
            subscription: subscription
        )
    }

    private func makeSubscription(_ subscription: DependencyPlan.Subscription) -> any SubscriptionService {
        switch subscription {
        case .apphud:
            return ApphudSubscriptionService(apiKey: Secrets.apphudAPIKey)
        case let .fake(isPremium):
            #if DEBUG
            return FakeSubscriptionService(isPremium: isPremium)
            #else
            return ApphudSubscriptionService(apiKey: Secrets.apphudAPIKey)
            #endif
        }
    }

    private func makeRepository(_ storage: DependencyPlan.Storage) async throws -> any ChatRepository {
        switch storage {
        case .disk:
            return try await GRDBChatRepository.launch(database: AppDatabase.onDisk())
        case .previewData:
            #if DEBUG
            let repository = PreviewData.repository()
            repository.markGeneratingAsInterrupted()
            return repository
            #else
            return try await GRDBChatRepository.launch(database: AppDatabase.onDisk())
            #endif
        }
    }

    private func makeConnectivity(_ network: DependencyPlan.Network) -> any ConnectivityMonitoring {
        switch network {
        case .system:
            return NetworkConnectivityMonitor()
        case .offline:
            #if DEBUG
            return FakeConnectivityMonitor(isOnline: false)
            #else
            return NetworkConnectivityMonitor()
            #endif
        }
    }
}
