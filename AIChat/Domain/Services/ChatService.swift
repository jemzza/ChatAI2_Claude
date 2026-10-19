import Foundation

/// Логика чата: отправка, ответ AI, «Retry»/«Regenerate», outbox, удаление.
///
/// - База — единственный источник правды; сервис только пишет в неё через `ChatRepository`.
///   Идёт ли генерация, экран узнаёт по статусу `generating` в базе.
/// - Запросом владеет сервис (живёт в `AppContainer`), а не экран: уход с экрана его не отменяет.
@MainActor
final class ChatService: ChatSession {
    private struct Generation {
        let messageId: UUID
        var task: Task<Void, Never>?
        /// Система забрала фоновое время — итог `interrupted`, а не `failed`.
        var interruptedBySystem = false
    }

    private let repository: any ChatRepository
    private let provider: any ChatProvider
    private let connectivity: any ConnectivityMonitoring
    private let backgroundTasks: (any BackgroundTaskScheduling)?
    /// Уведомления о готовом ответе и отправленном outbox.
    private let eventHandler: (any ChatEventHandling)?
    private let now: () -> Date

    /// Не больше одного запроса на чат.
    private var generations: [UUID: Generation] = [:]
    private var isProcessingOutbox = false
    private var isOutboxRerunRequested = false

    init(
        repository: any ChatRepository,
        provider: any ChatProvider,
        connectivity: any ConnectivityMonitoring,
        backgroundTasks: (any BackgroundTaskScheduling)? = nil,
        eventHandler: (any ChatEventHandling)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.repository = repository
        self.provider = provider
        self.connectivity = connectivity
        self.backgroundTasks = backgroundTasks
        self.eventHandler = eventHandler
        self.now = now
    }

    /// Идёт ли сейчас запрос в чате.
    func isGenerating(chatId: UUID) -> Bool {
        generations[chatId] != nil
    }

    // MARK: Жизненный цикл приложения

    /// Следит за сетью, пока жива задача вызывающего: первое значение — запуск,
    /// дальше каждое появление сети отправляет outbox.
    func run() async {
        for await isOnline in connectivity.updates() where isOnline {
            await processOutbox()
        }
    }

    /// Возврат в foreground — ещё один повод отправить outbox.
    func appDidBecomeActive() {
        Task { await processOutbox() }
    }

    // MARK: ChatSession

    func send(_ text: String, inChat chatId: UUID?) async throws -> UUID {
        let date = now()
        let chatId = chatId ?? UUID()
        // Всегда сначала `pending`: переход в `sent` вместе с ответом — атомарный
        // `claimPending`, тот же путь, что у outbox, поэтому двойной отправки нет.
        let message = Message(chatId: chatId, role: .user, text: text, status: .pending, createdAt: date)
        if try await chatExists(chatId) {
            try await repository.insertMessage(message)
        } else {
            let chat = Chat(id: chatId, title: ChatTitle.make(from: text), createdAt: date, updatedAt: date)
            try await repository.insertChat(chat, firstMessage: message)
        }
        if connectivity.isOnline, generations[chatId] == nil {
            _ = try await claimAndGenerate(message)
        }
        return chatId
    }

    func retry(assistantMessageId: UUID, inChat chatId: UUID) async throws {
        guard generations[chatId] == nil,
              let question = try await question(before: assistantMessageId, inChat: chatId),
              try await repository.claimRetry(assistantMessageId: assistantMessageId),
              // Пока ждали базу, мог стартовать outbox в этом же чате.
              generations[chatId] == nil
        else { return }
        startGeneration(chatId: chatId, messageId: assistantMessageId, question: question)
    }

    func deleteChat(id: UUID) async throws {
        // Запоздалая запись ответа получит `MessageNotFound` — её глотаем в `generate`.
        generations[id]?.task?.cancel()
        try await repository.deleteChat(id: id)
    }

    func deleteAll() async throws {
        for generation in generations.values { generation.task?.cancel() }
        try await repository.deleteAll()
    }

    // MARK: Outbox

    /// Отправляет `pending` по очереди: следующий — после того, как ответ на предыдущий готов.
    /// Повторные вызовы во время работы не запускают второй проход параллельно.
    /// Если что-то ушло — одно событие `queuedMessagesDidSend` на проход.
    func processOutbox() async {
        guard !isProcessingOutbox else {
            isOutboxRerunRequested = true
            return
        }
        isProcessingOutbox = true
        let sent = await drainOutbox()
        isProcessingOutbox = false
        if sent > 0 { await eventHandler?.queuedMessagesDidSend(count: sent) }
    }

    /// - Returns: сколько `pending` забрано и отправлено.
    private func drainOutbox() async -> Int {
        var sent = 0
        repeat {
            isOutboxRerunRequested = false
            guard connectivity.isOnline, let pending = try? await repository.pendingMessages() else { return sent }
            for message in pending {
                guard connectivity.isOnline else { return sent }
                // Чат занят — его сообщения уйдут, когда запрос закончится
                // (`finishGeneration` снова запускает outbox).
                guard generations[message.chatId] == nil else { continue }
                guard let task = try? await claimAndGenerate(message) else { continue }
                sent += 1
                await task.value
            }
        } while isOutboxRerunRequested
        return sent
    }

    /// Атомарно `pending` → `sent` + ответ `generating`; `nil` — сообщение уже забрали.
    private func claimAndGenerate(_ message: Message) async throws -> Task<Void, Never>? {
        // Ответ сразу после своего вопроса, даже если за ним уже стоят другие `pending`.
        let reply = Message(chatId: message.chatId, role: .assistant, text: "", status: .generating,
                            createdAt: message.createdAt.addingTimeInterval(0.001))
        guard try await repository.claimPending(messageId: message.id, reply: reply) else { return nil }
        return startGeneration(chatId: message.chatId, messageId: reply.id, question: message.text)
    }

    // MARK: Генерация

    @discardableResult
    private func startGeneration(chatId: UUID, messageId: UUID, question: String) -> Task<Void, Never> {
        generations[chatId] = Generation(messageId: messageId)
        let task = Task { [weak self] () -> Void in
            await self?.generate(chatId: chatId, messageId: messageId, question: question)
        }
        generations[chatId]?.task = task
        return task
    }

    private func generate(chatId: UUID, messageId: UUID, question: String) async {
        let backgroundToken = backgroundTasks?.beginTask { [weak self] in
            self?.generations[chatId]?.interruptedBySystem = true
            self?.generations[chatId]?.task?.cancel()
        }
        defer {
            if let backgroundToken { backgroundTasks?.endTask(backgroundToken) }
        }

        var text = ""
        var failure: MessageFailure?
        do {
            text = try await provider.reply(to: question, inChat: chatId)
        } catch let error as APIError {
            failure = MessageFailure(kind: error.kind, retryAt: error.retryAfter.map { retryDate(after: $0) })
        } catch {
            // Отмена без системы — чат удаляют: писать некуда, `MessageNotFound` проглотим ниже.
            if !Task.isCancelled { failure = MessageFailure(kind: .unknown) }
        }

        let status: MessageStatus
        if generations[chatId]?.interruptedBySystem == true {
            status = .interrupted
            failure = nil
        } else if failure != nil {
            status = .failed
        } else if Task.isCancelled {
            status = .cancelled
        } else {
            status = .done
        }
        // Запись — в отдельной задаче: отменённая генерация сама записать уже не может.
        let repository = repository
        let finalText = text
        let finalFailure = failure
        let saved = await Task {
            do {
                try await repository.updateMessage(id: messageId, text: finalText, status: status, failure: finalFailure)
                return true
            } catch {
                // `MessageNotFound` — чат удалён; прочее — ответ останется `generating`
                // и при следующем запуске станет `interrupted`.
                return false
            }
        }.value
        // Уведомление — пока фоновое время ещё наше (`endTask` — в `defer`).
        if saved, status == .done, !text.isEmpty {
            await eventHandler?.replyDidFinish(chatId: chatId, text: text)
        }
        finishGeneration(chatId: chatId, messageId: messageId)
    }

    private func finishGeneration(chatId: UUID, messageId: UUID) {
        guard generations[chatId]?.messageId == messageId else { return }
        generations[chatId] = nil
        // Пока шёл запрос, в чате могли накопиться `pending`.
        if connectivity.isOnline {
            Task { await processOutbox() }
        }
    }

    // MARK: Вспомогательное

    /// Вопрос, на который отвечает сообщение ассистента, — сообщение пользователя прямо перед ним.
    private func question(before assistantMessageId: UUID, inChat chatId: UUID) async throws -> String? {
        let context = try await repository.history(chatId: chatId, before: assistantMessageId, limit: 1)
        guard let last = context.last, last.role == .user else { return nil }
        return last.text
    }

    private func chatExists(_ chatId: UUID) async throws -> Bool {
        var chats = repository.observeChats().makeAsyncIterator()
        return await chats.next()?.contains { $0.id == chatId } ?? false
    }

    private func retryDate(after duration: Duration) -> Date {
        let (seconds, attoseconds) = duration.components
        return now().addingTimeInterval(Double(seconds) + Double(attoseconds) / 1e18)
    }
}
