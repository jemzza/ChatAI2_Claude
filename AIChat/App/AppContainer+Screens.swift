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
        /// `-mockSlowReply`: фейковый ответ через несколько секунд.
        case slowReply
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
            model = options.slowReply ? .slowReply : .live
        }
        subscription = options.mockPremium.map { .fake(isPremium: $0) } ?? .apphud
    }
}

/// Зависимости, общие для всех экранов.
@MainActor
struct AppDependencies {
    let repository: any ChatRepository
    let connectivity: any ConnectivityMonitoring
    let subscription: any SubscriptionService
    let chat: ChatService
    let videoRepository: any VideoRepository
    let videoAPI: any VideoAPI
    let media: any MediaStoring
    let video: VideoGenerationService
    let thumbnails: any VideoThumbnailing
    let photoAccess: any PhotoLibraryAccess
    let photoSaver: any PhotoSaving
    let settings: any SettingsStoring
    let notifications: any LocalNotificationScheduling
    let cache: any CacheManaging
}

extension AppContainer {
    /// Собирает зависимости экранов. Асинхронно: при запуске репозиторий переводит
    /// оборванные генерации в `interrupted` раньше, чем на базу подпишутся экраны.
    func makeDependencies() async throws -> AppDependencies {
        let plan = DependencyPlan(options: launchOptions)
        // Подписка — первой: её `userID` нужен каждому запросу к API.
        let subscription = makeSubscription(plan.subscription)
        // `-mockData`: и видео-история в памяти — демо-генерации не смешиваются с настоящими.
        let database = try plan.storage == .previewData ? AppDatabase.inMemory() : AppDatabase.onDisk()
        let repository = try await makeRepository(plan.storage, database: database)
        let connectivity = makeConnectivity(plan.network)
        let scheduler = UserNotificationScheduler()
        let notifications = NotificationService(
            settings: settings,
            scheduler: scheduler,
            activity: UIKitAppActivity(),
            repository: repository
        )
        let chat = ChatService(
            repository: repository,
            provider: makeChatProvider(plan.model, subscription: subscription),
            connectivity: connectivity,
            backgroundTasks: UIKitBackgroundTasks(),
            eventHandler: notifications
        )
        let videoRepository = GRDBVideoRepository(database: database)
        let videoAPI = makeVideoAPI(plan.storage, subscription: subscription)
        let media = try FileMediaStore.standard()
        let video = VideoGenerationService(
            repository: videoRepository,
            api: videoAPI,
            media: media,
            connectivity: connectivity,
            backgroundTasks: UIKitBackgroundTasks(),
            eventHandler: notifications
        )
        return AppDependencies(repository: repository, connectivity: connectivity,
                               subscription: subscription, chat: chat, videoRepository: videoRepository,
                               videoAPI: videoAPI, media: media, video: video,
                               thumbnails: makeThumbnails(plan.storage), photoAccess: SystemPhotoLibraryAccess(),
                               photoSaver: SystemPhotoSaver(), settings: settings, notifications: scheduler,
                               cache: FileCacheManager.standard())
    }

    /// `-mockData` — каталог и генерация видео из фейка (результат — mp4 из фото):
    /// экраны видео работают без сети.
    private func makeVideoAPI(_ storage: DependencyPlan.Storage,
                              subscription: any SubscriptionService) -> any VideoAPI {
        #if DEBUG
        if storage == .previewData { return DemoVideoAPI() }
        #endif
        return PixverseClient(api: nebulaAPI(service: "pixverse", subscription: subscription),
                              catalogCacheURL: Self.templatesCacheURL)
    }

    private func makeThumbnails(_ storage: DependencyPlan.Storage) -> any VideoThumbnailing {
        #if DEBUG
        if storage == .previewData { return FakeVideoThumbnails() }
        #endif
        return VideoThumbnailService.standard()
    }

    /// Последний каталог шаблонов — для работы без сети.
    private static var templatesCacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("pixverse-templates.json", isDirectory: false)
    }

    /// Клиент сервиса Nebula: `user_id` — Apphud User ID на момент запроса.
    private func nebulaAPI(service: String, subscription: any SubscriptionService) -> NebulaAPI {
        // Адрес задан в коде и проверен (docs/task.md, «Контракты API»).
        let baseURL = URL(string: "https://nebulaapps.site")?.appendingPathComponent(service)
            ?? URL(fileURLWithPath: "/")
        return NebulaAPI(
            client: APIClient(baseURL: baseURL),
            ownerToken: Secrets.nebulaAPIToken,
            appID: Self.apiAppID,
            userID: { await subscription.userID }
        )
    }

    /// `application_id` из ТЗ — под ним приложение заведено в API (не bundle id).
    static let apiAppID = "com.test.test"

    private func makeChatProvider(_ model: DependencyPlan.Model,
                                  subscription: any SubscriptionService) -> any ChatProvider {
        switch model {
        case .live:
            return DolaChatProvider(api: nebulaAPI(service: "dola", subscription: subscription))
        #if DEBUG
        case let .failing(kind):
            let retryAfter: Duration? = kind == .rateLimited ? .seconds(30) : nil
            return FakeChatProvider(script: .fail(APIError(kind: kind, retryAfter: retryAfter), delay: .seconds(1)))
        case .slowReply:
            return FakeChatProvider(script: .reply(Self.slowReply, delay: .seconds(4)))
        #else
        case .failing, .slowReply:
            return DolaChatProvider(api: nebulaAPI(service: "dola", subscription: subscription))
        #endif
        }
    }

    #if DEBUG
    /// Ответ фейка для `-mockSlowReply` (содержимое переписки, не строка интерфейса).
    private static let slowReply = """
        **Welcome to the team!**

        Here are a few tips:
        - Ask questions early;
        - Meet the team on Monday.
        """
    #endif

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

    private func makeRepository(_ storage: DependencyPlan.Storage,
                                database: AppDatabase) async throws -> any ChatRepository {
        switch storage {
        case .disk:
            return try await GRDBChatRepository.launch(database: database)
        case .previewData:
            #if DEBUG
            let repository = PreviewData.repositoryWithFolders()
            repository.markGeneratingAsInterrupted()
            return repository
            #else
            return try await GRDBChatRepository.launch(database: database)
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
