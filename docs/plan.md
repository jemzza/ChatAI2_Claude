# План

Агент выполняет шаги по одному, после каждого — сборка, отметка `[x]`, коммит.
Шаги с пометкой **👤** требуют действия пользователя — агент останавливается и просит.
Каждый UI-шаг: перед кодом — `get_design_context` / `get_screenshot` нужных
узлов Figma и заметок под ними; после — скриншот из симулятора рядом с макетом.

> План предыдущего проекта (стартовый AI-чат на Groq) — в истории git.

## 0. Перестройка каркаса

- [x] 0.1 Новое ТЗ: `docs/task.md`, `docs/plan.md`, `CLAUDE.md` под Figma,
      Dola/PixVerse, Apphud и iOS 16.
- [x] 0.2 `project.yml`: bundle `com.labs.fviu`, только iPhone/портрет,
      без Mac Catalyst, тёмная тема, ApphudSDK (`exactVersion`), строки
      доступа к Фото. `Build.command` — новый bundle id.
- [ ] 0.3 Убрать то, что не входит в ТЗ: Groq, Foundation Models, голос,
      старые настройки/сайдбар, их тесты и строки каталога. Временный корневой
      экран-заглушка. Сборка и тесты зелёные.
- [ ] 0.4 iOS 16: `deploymentTarget` → 16.0; ViewModel → `ObservableObject`;
      `Mutex` → свой лок; убрать API iOS 17+ или спрятать за `#available`.
      Сборка под iOS 16.
- [ ] 0.5 **👤** Секреты: `gen_secrets.py` читает `NEBULA_API_TOKEN` и
      `APPHUD_API_KEY`; пользователь запускает скрипт. Тест формы ключей
      (`eyJ…`/`app_…`, длина), значения → `Bool` до `#expect`.

## 1. Сеть

- [ ] 1.1 `HTTPClient` + `Endpoint` (JSON и multipart) + маппинг в `APIError`
      по таблице; тесты на `URLProtocol`-стабе.
- [ ] 1.2 Сессия API: `auth/session`, `auth/refresh`, Keychain, повтор на 401;
      отдельно для Dola и PixVerse. Тесты.
- [ ] 1.3 Проверка реальными запросами (`health`, `auth/session`,
      `templates`, `chats/{id}/messages`): базовые URL и реальная форма
      ответа шаблонов — в `docs/task.md`. Токен не печатать.

## 2. Подписка (Apphud)

- [ ] 2.1 `SubscriptionService` (Domain) + `ApphudSubscriptionService` (Data) +
      фейк: старт SDK, `userID` для API, `isPremium` с обновлением после покупки.
- [ ] 2.2 Пейвол-данные: продукты пейвола `main`, покупка, restore, ошибки;
      тесты ViewModel на фейке.

## 3. Чат: данные и логика

- [ ] 3.1 Миграция: `chat.pinnedAt`, статус `generating` вместо `streaming`;
      репозиторий (pin/unpin), контрактные тесты.
- [ ] 3.2 `DolaChatProvider` + переделка `ChatService` под ответ целиком:
      отправка, outbox, regenerate, retry, interrupted при запуске; тесты.

## 4. Видео: данные и логика

- [ ] 4.1 Модели `VideoTemplate`, `VideoGeneration`; миграция таблицы;
      `VideoRepository` (GRDB + in-memory), контрактные тесты.
- [ ] 4.2 `PixverseClient`: шаблоны, `template2video` (multipart), `status`; тесты.
- [ ] 4.3 `VideoGenerationService`: кроп под формат, создание, опрос статуса,
      возобновление при запуске, скачивание файла, «Try again», `isViewed`,
      уведомление «видео готово»; тесты.

## 5. UI-основа

- [ ] 5.1 Дизайн-токены из Figma: цвета, градиенты, типографика, радиусы,
      отступы → `Assets.xcassets` + `Theme`.
- [ ] 5.2 Переиспользуемые компоненты: градиентная кнопка, чип, тост
      (2 с, свайп вверх), строка настроек, шапка экрана, поле ввода; `#Preview`.
- [ ] 5.3 Навигация: роутер на `NavigationStack`, поток Splash → Onboarding →
      Paywall → Main, показ пейвола из любого места.

## 6. Экраны

- [ ] 6.1 Splash + Onboarding (2 страницы, индикатор, свайп, Continue).
- [ ] 6.2 Paywall: продукты, выбор плана, «Unlock now», крестик через 2 с,
      Restore, ссылки, состояния загрузки/ошибки.
- [ ] 6.3 Main: варианты Free/Premium, PRO, «Ask anything…», карточка видео.
- [ ] 6.4 AI Chat: пустое состояние с чипами, поле ввода (до 3 строк, дальше
      скролл), Send ↔ пейвол, анимация генерации, ответ с Markdown,
      Copy/Regenerate, тосты Copied/Copy failed.
- [ ] 6.5 Меню чата: Share, Pin/Unpin, Delete с подтверждением.
- [ ] 6.6 Templates: категории (горизонтальный скролл), сетка, фильтр,
      загрузка/ошибка.
- [ ] 6.7 Template Preview: листание шаблонов, разрешение к Фото, выбор фото,
      загрузка/«Upload failed», × у фото, Format и Quality, Create.
- [ ] 6.8 Generating + Result: анимация, фоновая генерация, плеер
      (play/pause, по кругу, 16:9/9:16/1:1), Replace, Share, Download,
      «Video saved» / «Couldn't save video».
- [ ] 6.9 History: Chat | Video; Pinned и группы по дате, свайп
      Rename/Delete, алерты; сетка видео masonry с In progress / New / Error +
      Try again; пустые состояния.
- [ ] 6.10 Папки в History → Chat: создать/переименовать/удалить, «Move to folder».
- [ ] 6.11 Settings: все строки макета (Rate, Share, Upgrade, Notifications,
      Clear cache с размером, Restore, Contact, Privacy, Usage, версия).

## 7. Полировка и сдача

- [ ] 7.1 DEBUG launch-аргументы: `-mockOffline`, `-mockError <code>`,
      `-mockPremium`/`-mockFree`, `-skipOnboarding`; UI-тесты ключевых потоков.
- [ ] 7.2 Анимации и переходы, haptics, память (плеер, даунсемплинг
      картинок), Instruments на утечки.
- [ ] 7.3 Прогон на iOS 16 и iOS 26: сценарии из README, ошибки через
      launch-аргументы, покупка/restore в sandbox.
- [ ] 7.4 README, честный раздел «Не сделано», `git grep` на ключи.

## Журнал отклонений от плана

_Сюда записываем, что пошло не так и что решили иначе._

- 0.2: `deploymentTarget` остался 18.0 — стартовый код использует `Mutex`,
  `@Observable` и другие API iOS 17–18, сборка под 16 падает. Переключение на
  16.0 перенесено в 0.4, вместе с переводом кода. Строки микрофона и
  распознавания речи в Info.plist удалим в 0.3 вместе с голосом.
