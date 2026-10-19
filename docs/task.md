# Задача

Тестовое задание iOS-разработчика: приложение с двумя модулями — **AI Text
Chat** и **AI Video Generator** — плюс онбординг, пейвол (Apphud), история
чатов/видео и настройки. Интерфейс — максимально точно по макету Figma.
Оценивают качество кода, архитектуру, аккуратность UI, работу с API,
интеграцию Apphud, отсутствие багов, производительность и плавность анимаций.

Проект вырос из стартового AI-чата (MVVM, offline-first, GRDB, XcodeGen):
каркас, слои, база, локализация и правила работы сохранены, фичи
переделаны под новое ТЗ.

## Исходные данные

- **Figma:** `https://www.figma.com/design/7X0uQl95zcP3KPMmB1G8ix/` (fileKey
  `7X0uQl95zcP3KPMmB1G8ix`), читаем через Figma MCP. Секции:
  `Splash & Onboarding → Paywall` (`40022989:3378`),
  `Main page (AI Chat)` (`40022989:2658`), `Video Generator` (`40022989:3014`),
  `History` (`40022989:3522`), `Settings` (`40022989:3820`). У каждого экрана
  под макетом — заметка с поведением; она такая же часть ТЗ, как картинка.
- **API** (сервер всегда отвечает одинаково, но запросы — настоящие):
  - Чат — Dola: `https://nebulaapps.site/dola/docs`.
  - Видео — PixVerse: `https://nebulaapps.site/pixverse/docs`.
  - `app_id` = `com.test.test`, `user_id` = Apphud User ID.
  - Bearer-токен владельца — только через `scripts/gen_secrets.py` (см. CLAUDE.md).
- **Apphud:** bundle `com.labs.fviu`, paywall id `main`, API-ключ — только через
  `scripts/gen_secrets.py`.

## Обязательные требования

- [ ] SwiftUI, минимум **iOS 16**; работает на iOS 16 и на последней iOS.
- [ ] Чистая архитектура (MVVM + слои), читаемый код, без падений.
- [ ] UI по Figma: отступы, шрифты, цвета, иконки, анимации, навигация.
- [ ] Плавные переходы, корректные состояния загрузки, без лагов и скачков.
- [ ] Сетевой слой, реальные запросы, состояния Loading / Success / Error.
- [ ] Apphud: пейвол по макету, проверка подписки, закрытый премиум-контент,
      доступ открывается сразу после покупки без перезапуска.
- [ ] Онбординг, пейвол, история чатов/видео, настройки.
- [ ] XcodeGen (`project.yml`), `Build.command`, зависимости только SPM.

## Решения

| Вопрос | Решение | Почему |
|---|---|---|
| UI | SwiftUI, `NavigationStack` | Нативно, iOS 16+ |
| Минимальная iOS | **16.0** (решение заказчика) | Требование ТЗ |
| ViewModel | `ObservableObject` + `@Published`, `@MainActor`; во View — `@StateObject`/`@ObservedObject` | `@Observable` только с iOS 17. Всё, что новее iOS 16 (`onChange` с двумя параметрами, `.sensoryFeedback`, `ContentUnavailableView`, `.scrollPosition` и т.п.), — только за `#available` |
| Архитектура | MVVM + offline-first: GRDB — единственный источник правды для чатов и видео; экраны читают базу через `ValueObservation`; сеть пишет в базу через сервисы | Сохраняем подход стартового проекта: история переживает перезапуск и работу без сети |
| Сервисы | `ChatService` и `VideoGenerationService` живут в `AppContainer` и владеют сетевыми задачами | Уход с экрана не отменяет генерацию ответа или видео (по макету видео генерируется в фоне и появляется в History) |
| Чат: ответ | Dola отвечает целиком (`assistant_message`), стриминга нет. Пока ждём — анимация «печатает» из макета; готовый ответ появляется плавно | API без стриминга; «Стоп» по макету нет — во время генерации кнопка Send неактивна |
| Чат: id | `chat_id` генерирует клиент (UUID строкой, сервер принимает); история — локальная, с сервера не синхронизируем | Сервер хранит чаты на пару user+app; источник правды — локальная база |
| Версия API и авторизация | **v1** у обоих сервисов: `Authorization: Bearer <токен владельца>` + query `user_id` (Apphud User ID) и `app_id=com.test.test` в каждом запросе | Проверено реальными запросами (шаг 1.3): у Dola маршруты `/api/v3/*` на сервере отдают 404, v1 работает; набор данных в ТЗ (Bearer + user_id + application_id) — ровно под v1. Клиентские сессии v3 (шаг 1.2) не используем, код удалён |
| Сетевой слой | Свой `HTTPClient` на `URLSession` + `async/await`, `Endpoint` (метод, путь, query, тело JSON/multipart), декодирование `Decodable`, маппинг ошибок в `APIError` | Без Alamofire: задач мало, лишняя зависимость не нужна |
| Шаблоны видео | `GET /api/v1/get_templates/com.test.test` → `templates` (879 шт.). Категории — поле `category` (с эмодзи, «✨ Other» — 742 шт.); чипы категорий строим из данных, «Popular» из макета — первая категория по порядку ответа/«📈 Trending». Превью (`preview_small`/`preview_large`) — **mp4**: в сетке — первый кадр (`AVAssetImageGenerator`, кэш), на экране шаблона — беззвучное видео по кругу. В запрос генерации идёт `template_id` (Int64), не `id` | Реальный ответ API |
| Видео: формат | В API `template2video` нет параметра соотношения сторон. Выбранный формат (16:9 / 9:16 / 1:1) — центр-кроп фото перед отправкой; результат показывается в контейнере этого формата | Иначе выбор формата из макета ничего бы не менял |
| Видео: качество | В API — `360p/540p/720p/1080p` (у шаблона — свой список `qualities`). В макете 720p / 1080p / 4K — **открытый вопрос** к заказчику: 4K в API нет | См. «Открытые вопросы» |
| Видео: статус | Опрос `GET /api/v1/status?id=` с интервалом 3 с → 5 с → 10 с; при запуске приложения опрос возобновляется для всех `generating` | Пуш-уведомлений от сервера нет |
| Видео: файл | Готовое видео скачивается в `Caches/Videos/` и проигрывается локально (`AVPlayer`, по кругу); «Download» — в Фото (`PHPhotoLibrary`, add-only); «Share» — системный share sheet с файлом | Быстрый повторный показ, работа без сети; «Clear cache» в настройках чистит эту папку |
| Подписка | Apphud SDK (SPM, обоснование ниже) за протоколом `SubscriptionService` (Domain): `isPremium` (`AsyncStream`/`@Published`), `paywallProducts()`, `purchase`, `restore`, `userID` | ViewModel не знает про Apphud; фейк для превью и тестов. Статус обновляется делегатом Apphud — доступ открывается сразу после покупки |
| Премиум-контент | Без подписки: отправка в чате и «Create» видео открывают пейвол (введённый промпт/выбранное фото сохраняются). Просмотр истории, шаблонов и настроек — доступен | Заметки к макетам «Main Page — Free User» и «AI Chat — Prompt Entered» |
| Пейвол | Показ: после онбординга, по кнопке PRO, «Upgrade plan» в настройках, при попытке премиум-действия. Крестик — через 2 с, еле заметный. Цены — из продуктов пейвола Apphud `main`; «Cancel anytime» не нажимается | Заметки к макету пейвола |
| Онбординг | Сплэш с прогрессом → 2 экрана (свайп или Continue) → пейвол → главный. Показывается один раз (`UserDefaults`) | Заметки к макету |
| Тема | Только тёмная, как в макете (`UIUserInterfaceStyle = Dark`) | В Figma нет светлых экранов |
| Цвета/шрифты | Токены из Figma (`get_variable_defs`) → `Assets.xcassets` и `Theme`; градиенты — именованные в `Theme`. Шрифт — системный SF Pro с Dynamic Type | Без захардкоженного RGB в View |
| Анимация загрузки видео | Кольцо из макета — на SwiftUI, без Lottie | Без лишней зависимости; при несовпадении с макетом — вопрос заказчику |
| Папки | Сохранены из стартового проекта; доступны только в History → Chat (секция «Folders», «Move to folder» в меню чата) | Решение заказчика |
| Закреплённые чаты | `chat.pinnedAt: Date?` (миграция GRDB); в History — секция «Pinned» сверху; иконка 📌 у названия в шапке чата | Макеты «Pinned Chat», «History — Chat List» |
| Уведомления | Переключатель в настройках: локальное уведомление «видео готово», если приложение не активно | Строка «Notifications» в макете настроек |
| Язык | Английский, все строки через `Localizable.xcstrings`, русский — переводом каталога | Как в стартовом проекте |
| Устройства | Только iPhone, портрет | Макеты только под iPhone |

### Зависимости

- **GRDB 7** (`exactVersion`) — база, `ValueObservation`.
- **ApphudSDK** (`exactVersion`) — требование ТЗ: покупки, пейвол, статус подписки.

## Контракты API (проверено реальными запросами 2026-10-19)

Базовые URL: `https://nebulaapps.site/dola`, `https://nebulaapps.site/pixverse`.
Во всех запросах: `Authorization: Bearer <токен>`, query `user_id`, `app_id`.
JSON — `snake_case`. Фикстуры ответов — `AIChatTests/Fixtures/`.

| Запрос | Ответ |
|---|---|
| `POST /dola/chats/{chat_id}/messages` JSON `{"message": …}` | 200 `{chat_id, assistant_message, images: []}`; песочница всегда отвечает одним текстом. 402 — нет кредитов |
| `GET /dola/chats` | 200 `[{chat_id, title?, persona_id?, updated_at, last_message_preview?}]` (`updated_at` без зоны: `2026-10-19T14:53:40`) — не используем |
| `GET /dola/chats/{chat_id}/messages` | 200 `[]` в песочнице — не используем |
| без Bearer | 401 `{"detail": "Missing authorization header"}` |
| `GET /pixverse/api/v1/get_templates/{app_id}` | 200 `{templates: [{id, template_id, name, category, duration, preview_small, preview_large (mp4), prompt, qualities, is_active (0/1)}], template_image, styles, …}` |
| `POST /pixverse/api/v1/template2video` multipart `template_id`, `image` (JPEG), `quality`, `duration?` | 201 `{video_id, detail}` |
| `GET /pixverse/api/v1/status?id=` | 200 `{status: generating/success/error, video_url?}`; неизвестный id — 404 `{"detail": "Generation not found"}` |
| `GET /pixverse/api/v1/balance` | 200 `{balance}` — не используем |

## Модель данных (Domain/Models)

- `Chat`: `id`, `title`, `createdAt`, `updatedAt`, `folderId?`, `pinnedAt?`.
- `Message`: `id`, `chatId`, `role` (`user`/`assistant`), `text`, `status`,
  `failure?`, `createdAt`.
  - user: `pending` (нет сети / ждёт) → `sent`.
  - assistant: `generating` → `done` | `failed` | `interrupted` (приложение
    закрыли во время запроса). Повтор («Regenerate» последнего ответа,
    «Retry» у ошибки) — атомарный `claimRetry`.
- `Folder`: как в стартовом проекте.
- `VideoTemplate`: `id` (= `template_id`, Int64), `name`, `category`,
  `previewURL` (mp4), `qualities`, `duration` (форма — «Контракты API»).
- `VideoGeneration`: `id` (UUID), `templateId`, `templateTitle`, `serverId?`,
  `status` (`uploading` → `generating` → `success` | `failed`), `aspect`
  (`16:9`/`9:16`/`1:1`), `quality`, `sourceImagePath` (для «Try again»),
  `videoURL?`, `localVideoPath?`, `isViewed` (бейдж «New»), `failure?`, `createdAt`.
- `APIError`/`ErrorKind`: `offline`, `unauthorized` (401 после refresh),
  `paymentRequired` (402, нет кредитов), `forbidden` (403), `rateLimited` (429),
  `validation` (422), `server` (5xx), `decoding`, `unknown`.

## Маппинг ошибок

- `URLError` → `offline`: `notConnectedToInternet`, `networkConnectionLost`,
  `dataNotAllowed`, `timedOut`, `cannotFindHost`, `cannotConnectToHost`; прочие → `unknown`.
- `CancellationError`, `URLError.cancelled` — не ошибка (уход с экрана/отмена).
- HTTP: 401 → refresh → повтор один раз → `unauthorized`; 402 → `paymentRequired`;
  403 → `forbidden`; 404 у `status` → `failed` генерации; 422 → `validation`;
  429 → `rateLimited` (+ `retry-after`); 5xx → `server`; прочее → `unknown`.
- Тексты ошибок не содержат токены, URL с параметрами и сырой ответ сервера.
- У каждой ошибки — понятный текст и действие «Try again» (по макету: тосты
  «Copy failed», «Upload failed», «Couldn't save video», карточка «Error» в
  истории видео).

## Offline-first: поведение

1. Сообщение пользователя сразу пишется в базу. Есть сеть — ответ ассистента
   создаётся в статусе `generating` и уходит запрос; нет — `pending`, сообщение
   уйдёт само при появлении сети, запуске и возврате в foreground — ровно один
   раз (атомарный `claimPending`).
2. При запуске: `generating`-ответы → `interrupted` (с «Retry»);
   `generating`-видео — продолжаем опрос статуса.
3. Удаление чата во время запроса отменяет его `Task`; запоздалая запись
   получает `MessageNotFound` и глотается.
4. История чатов и видео доступна без сети; готовые видео — из локального файла.

## Навигация (по макету)

```
Splash → (первый запуск) Onboarding 1 → Onboarding 2 → Paywall → Main
Main: [History] [PRO — только free] [Settings]
  ├─ «Ask anything…» → AI Chat (новый)   ── free: Send → Paywall
  ├─ «Turn Photo into Video» → Templates → Template Preview → (Create) Generating → Result
  │                                                             free: Create → Paywall
  ├─ History: Chat | Video  → чат / результат видео
  └─ Settings
```

## Открытые вопросы к заказчику

- Качество 4K из макета: в API его нет — показывать только 720p/1080p или
  оставить 4K с отправкой 1080p?
- Ссылки Privacy Policy / Usage Policy / Terms of Use, адрес «Contact us»,
  ссылка на App Store для «Rate app» и «Share with friends».

## Известные риски

- Рантайм симулятора iOS 16 нужно скачать отдельно (Xcode 26 его не содержит).
- Покупки Apphud в симуляторе — через StoreKit Configuration / sandbox; без
  продуктов в App Store Connect цены могут не прийти — нужен понятный fallback.
- Симулятор на машине разработки не резолвит DNS (`-1003`), хотя с Mac сервер
  доступен (VPN?). Реальные запросы проверены с Mac консольной пробой; запуск
  приложения в симуляторе против реального API — проверить в 7.3.
- Баланс PixVerse = 0, но песочница генерирует (сразу `success`).

## Вне рамок

Голос, Foundation Models, Mac Catalyst, iPad-раскладка, светлая тема, свой
бэкенд/прокси.
