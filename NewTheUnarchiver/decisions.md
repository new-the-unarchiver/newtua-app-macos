# Журнал принятых решений — NewTheUnarchiver (macOS GUI)

Единый источник правды по договорённостям между человеком и Claude Code
по разработке macOS-приложения. Все промежуточные решения пишем сюда
с датой, чтобы при возвращении к задаче не приходилось восстанавливать
контекст из чата.

**Формат записи:**
- `## YYYY-MM-DD — Краткая тема`
- Суть решения одним-двумя предложениями.
- При необходимости — **Почему:** причина (особенно если решение
  неочевидно или противоречит «по умолчанию»).
- Открытые вопросы помечать `⚠ Открыто:` в конце соответствующей записи.

---

## 2026-06-22 — Базовые рамки проекта

- **Цель GUI:** повторить пользовательский сценарий оригинального
  The Unarchiver (drop → очередь → прогресс → готово) на современном
  SwiftUI для macOS 26+.
- **Что НЕ делаем на v1:** выборочная распаковка содержимого,
  потоковое чтение крупных entries, графики скорости (Charts).
- **Что делаем на v1 сверх оригинала:** Quick Look на содержимом
  архива — реализуем красиво, с использованием возможностей macOS.

## 2026-06-22 — Сценарии открытия архива

Три пользовательских сценария, два пути в коде:
1. **Drag на окно приложения** → `dropDestination(for: URL.self)`
   на корневом view.
2. **Drag на иконку Dock / двойной клик в Finder / «Открыть с помощью»
   через контекстное меню Finder** — все три идут через один системный
   механизм (Launch Services + `CFBundleDocumentTypes`/UTI в Info.plist),
   обрабатываем единым хэндлером открытия файлов.
3. **File ▸ Open…** → `fileImporter`.

## 2026-06-22 — Папка-обёртка (Never / Only if more / Always)

Все три варианта реализуем **в Swift**, без правок Rust-ABI:
- `Never` → `wrapper: false`.
- `Only if there is more than one top-level item` → `wrapper: true`
  (поведение по умолчанию движка, уже соответствует оригиналу).
- `Always` → перед `extract` локально по `entries()` проверяем,
  есть ли уже общий корень; если есть — всё равно создаём обёртку
  по имени архива поверх (механизм уточним при реализации).

## 2026-06-22 — macOS metadata, Threshold, security-scoped bookmarks

- **Keep macOS metadata** — в UI не показываем. Оставляем хардкод
  движка: всегда пропускаем `._*`, `.DS_Store`, `__MACOSX/`.
- **Threshold для автодетекта кодировки** — в UI не показываем
  (используем другое решение в движке, поле не нужно).
- **Security-scoped bookmarks** — не используем.
  **Почему:** распаковка — одноразовый акт в новом контексте,
  запоминать доступ к папке между запусками бессмысленно.

## 2026-06-22 — Видимость окна очереди

Повторяем поведение оригинального The Unarchiver: окно очереди
появляется при появлении задачи и автоматически сворачивается,
когда очередь пустеет. Не держим окно постоянно открытым.

## 2026-06-22 — Состояния задачи (ArchiveJob)

UI показывает только два видимых состояния: «в очереди»
(имя + иконка формата + кнопка ×) и «работает» (то же + прогресс-бар +
текущий извлекаемый файл). Промежуточные стадии (`opening`, `ready`,
подсчёт entries) пользователю не показываем — внутри они есть,
снаружи скрыты.

## 2026-06-22 — Конкурентность внутри одной задачи

По варианту (B) из обсуждения и в полном соответствии с § 4
технического брифа: один `DispatchQueue(label:)` на каждый `ArchiveJob`,
все вызовы `Archive` (`entries`, `read`, `extract`) идут через него.
Прогресс-колбэк хопит на `@MainActor` для обновления UI.

## 2026-06-22 — Кооперативная отмена

Собственная структура `CancellationToken` на базе
`OSAllocatedUnfairLock<Bool>`. Кнопка «×» в UI зовёт `cancel()`,
прогресс-колбэк (живёт в C-потоке движка) читает `isCancelled`
без перехода в actor.
**Почему не `Task.cancellation`:** колбэк не находится внутри
Swift `Task`, он вызывается из чужого потока движка.

## 2026-06-22 — Частота обновления прогресса в UI

Цель — минимально достаточная для плавного восприятия глазом,
не больше. Ориентир ~24 Гц (порог плавности анимации). Колбэк
движка может вызываться чаще — троттлинг на стороне `ArchiveJob`
перед хопом на `@MainActor`. Не дёргать SwiftUI чаще, чем нужно.

## 2026-06-22 — Параллельная распаковка

Используем параллель, когда это безопасно по совместимости задач.

**Блокеры параллельности (две задачи не могут идти одновременно, если):**
- Хотя бы одна из них на внешнем носителе или на HDD.
- Хотя бы одна запароленная (требует ввода пользователя — естественная
  сериализация).
- У них общая папка назначения.

**Архитектурное решение:** не семафор с фиксированным числом, а
**планировщик с предикатом совместимости**. При освобождении слота
из очереди берётся первая задача, совместимая со всеми текущими
работающими.

**Технические решения для детекта:**
- Внешний/внутренний: `URLResourceValues.volumeIsInternalKey`.
- SSD/HDD: через IOKit + Disk Arbitration (BSD-name → IOMedia →
  IOBlockStorageDevice → `Device Characteristics` → `Medium Type`).
  Результат кешировать по mount-path. При неудаче детекта —
  фолбэк «считаем HDD/внешним», то есть не параллелим. Это
  безопасный дефолт.
- Общая папка назначения: сравнение `URL.standardizedFileURL`.

**Уровень параллелизма:** статический потолок
`min(ProcessInfo.activeProcessorCount, 4)`. Динамический мониторинг
загрузки CPU не используем — лишний шум, прирост сомнительный.

**Скоуп:** делаем в v1 целиком, сразу с планировщиком совместимости.
Без промежуточной «тупой» реализации с семафором.
**Почему:** переход с глупого семафора на планировщик потом
требует переписывать модель задач — дешевле заложить совместимость
сразу.

## 2026-06-22 — Пароль и кодировка (повторное открытие Archive)

Реализуем ровно как требует ABI (§ 6 брифа):

- При `.encrypted` / `.wrongPassword` на `ntua_open` → задача
  встаёт в состояние `needsPassword`, показывается встроенный
  блок ввода пароля → получив пароль, создаём **новый**
  `Archive(path:, password: …)`.
- При смене кодировки пользователем в встроенном блоке выбора
  кодировки → создаём новый `Archive(path:, encoding: …)` для
  обновления превью `Result:` (на каждой смене значения).
  Эти реопены лёгкие — открытие не парсит содержимое, только
  заголовки и список имён.
- **Apply to All:** включаем как в оригинале. Если пользователь
  ввёл пароль с включённой галочкой «Apply to All», он
  запоминается на уровне `AppModel` (только в памяти, до выхода
  из приложения) и автоматически подставляется как первая попытка
  для следующих запароленных архивов в очереди. Если не подошёл —
  обычный запрос пароля.

## 2026-06-22 — Локализация (RU + EN обязательны к релизу)

К релизу v1 приложение поставляется **минимум в двух локалях: русской
и английской**. Локализация — сквозное требование на всех этапах,
не отдельный финальный этап.

**Что берётся от движка, что локализуем сами:**
- **От движка** (`ntua_error_message(status, lang)`): только
  динамические сообщения по коду статуса. EN/RU уже встроены.
- **Локализуем сами** в приложении: всё остальное — заголовки,
  меню, кнопки, тултипы, плейсхолдеры, подписи в очереди, inline-блоки
  пароля/кодировки, Preferences, уведомления, Quick Look-сообщения
  не от движка.

**Технически:**
- Все пользовательские строки — в `Localizable.xcstrings`
  (String Catalog). Никаких хардкод-строк в `Text(...)` / алертах /
  уведомлениях / заголовках окон / меню.
- В SwiftUI — `Text("key")`; в не-View контекстах —
  `String(localized: "key")`.
- Множественные числа — variations в `Localizable.xcstrings`.
- **Строки на обеих локалях создаёт ассистент сам** в момент добавления
  ключа. Человек переводы не пишет.

**На каждом этапе:** новые строки добавляются в каталог сразу,
в обеих локалях, в момент написания TDD-тестов. В критерий завершения
этапа входит «строки переведены на RU и EN».

**Перед релизом v1:** запуск под `-NSShowNonLocalizedStrings YES`,
ручная проверка обоих локалей по сценариям этапов 4–9.

## 2026-06-22 — Расширение методологии (10 подшагов вместо 6)

Методология цикла на каждом этапе расширена с 6 до 10 подшагов:
после прохождения полного тестового набора (шаг 6) добавляются
**обязательные шаги ревью**:

7. Краткий код-ревью (дубли, мёртвый код, уязвимости, ошибки,
   переусложнения, неэффективности) → список проблем.
8. Анализ списка: отсев ложных срабатываний и несущественного.
9. Исправление подтверждённых проблем.
10. Повторный прогон полного набора до зелёного.

**Почему:** базовый TDD-цикл даёт правильное поведение, но не
гарантирует качество кода. Явная фаза ревью между этапами не
даёт техдолгу копиться.

Источник правды по тексту методологии — `plan.md` (там его обновляет
человек) и `CLAUDE.md` (синхронизируется по нему).

## 2026-06-22 — Этап 0 завершён

Обёртка `Newtua` модернизирована:
- Введены публичные Swift-native типы: `ErrorCode` (заменяет `NtuaStatus`
  в `NewtuaError.code`), `Progress` (заменяет `NtuaProgress`),
  `CancellationToken` (на `OSAllocatedUnfairLock<Bool>`).
- У `Archive` появились `async`-перегрузки `extract`/`read`, каждая
  диспетчеризируется на личный `DispatchQueue(label: "newtua.archive.<uuid>")`.
- Прогресс-колбэк в async-варианте хопит на `@MainActor` и фильтруется
  по `token.isCancelled` после хопа, чтобы не дёргать UI после отмены.
- Sync-перегрузки сохранены — колбэк там идёт на потоке движка.
- Все публичные колбэки помечены `@Sendable` под Swift 6 strict
  concurrency.
- `swift-tools-version` пакета поднят до `6.0`, `platforms = .macOS(.v14)`.

Шаблонный SwiftData-скаффолд приложения вычищен:
- Удалён `Item.swift`.
- Из `NewTheUnarchiverApp.swift` убраны `import SwiftData`, `import CNewtua`,
  `Schema`, `ModelContainer`, `.modelContainer(...)`.
- `ContentView.swift` сведён к плейсхолдеру.

**Тесты:** 19 новых на Swift Testing (5 TDD-минимум + 14 расширенных) +
4 legacy XCTest, мигрированных на новый API. Все зелёные.
**Сборка Xcode-приложения:** `BuildProject` без ошибок.

## 2026-06-22 — Этап 0: фаза ревью (шаги 7–10 методологии)

После прогона полного набора прошли три параллельных ревью-агента
(reuse / quality / efficiency). Из найденных проблем приняты к исправлению:

- **`Entry.kind: String` → `enum EntryKind`** (`.file`/`.dir`/`.symlink`).
  Убраны stringly-typed сравнения в тестах.
- **`NewtuaError: Equatable`** — упрощает `#expect` в будущих тестах.
- **Общий `TestSupport.swift`** с `repoRoot`/`fixture(_:)`/`makeTempDir(prefix:)`.
  Дубли в `Stage0Tests`/`Stage0ExtendedTests` устранены.
- **Удалён legacy XCTest-файл `NewtuaTests.swift`** (4 теста). Все его
  проверки покрыты Swift Testing-набором; `testVersion` перенесён в
  `Stage0ExtendedTests` как `version_isNonEmpty`.
- **Уточнён комментарий к `@unchecked Sendable` на `Archive`**: явно
  описан контракт «не вызывать методы на одном Archive из двух потоков
  одновременно».
- **Удалены Xcode-header-комментарии** из `NewTheUnarchiverApp.swift` и
  `ContentView.swift`; убран комментарий-ссылка на этап плана из тела
  плейсхолдера.

Отклонены как ложные срабатывания или преждевременная оптимизация:
- Переименование `extract`/`read` async-перегрузок в `extractAsync`/
  `readAsync` — оверлоадинг идиоматичен для Swift, тесты дизамбигируют
  через явное `: Data`/`: ExtractReport` где нужно.
- `ExtractOptions`-структура для устранения дубля параметров — пока
  два места повтора, абстракция станет уместной при росте параметров.
- `lazy var queue` — стоимость создания `DispatchQueue` пренебрежимо
  мала, отложенная инициализация добавит сложности.
- Оптимизации горячего пути прогресс-колбэка (аллокация замыкания при
  хопе на main, два захвата unfair lock на тик) — планово закрываются
  тротлингом в Этапе 2.
- Дроп `@testable import Newtua` в тестах — отклонено: тесты используют
  internal-конструктор `ErrorCode.init?(NtuaStatus)` для верификации
  mapping-таблицы. Этот конструктор намеренно internal, чтобы прикладной
  код не зависел от `CNewtua`.

**Повторный прогон тестов:** 20 тестов Swift Testing, все зелёные.
**`BuildProject`:** без ошибок.

## 2026-06-22 — Коммиты после каждого этапа

С этого момента каждый завершённый этап плана закрывается отдельным
git-коммитом сразу после прохождения шага 10 методологии. Не пушим.
**Почему:** удобнее ориентироваться в истории и при необходимости
откатывать или сравнивать этапы.

## 2026-06-22 — Ветка macapp

Дальнейшая разработка GUI ведётся в ветке `macapp` (отделена от `dev`
после коммита Stage 0). Merge в `dev` — по готовности набора этапов.
**Почему:** дать `dev` оставаться чистым по своим (rust/ffi/i18n)
задачам, а GUI-история жила в собственном русле.

## 2026-06-23 — Этап 1 завершён

Доменная модель (pure Swift, без UI, без движка):
- `Domain/JobState.swift` — enum состояний (`queued`, `running`,
  `needsPassword(PasswordReason)`, `needsEncoding(currentEncoding:)`,
  `succeeded(ExtractReport)`, `failed(ErrorCode)`, `cancelled`),
  `isTerminal`, `canTransition(to:)`.
- `Domain/ArchiveJob.swift` — `@MainActor @Observable` задача с
  `id`, `url`, `state`, `progress`, личным `CancellationToken`,
  методами `updateState`, `cancel`, `recordProgress`.
- `Domain/AppModel.swift` — `@MainActor @Observable` корень с
  `queue: [ArchiveJob]`, `sharedPassword: String?`,
  `extractionOptions`, методами `enqueue(urls:)`, `remove(_:)`,
  `setSharedPassword(_:applyToAll:)`, `clearSharedPassword()`.
- `Domain/ExtractionOptions.swift` — value-тип с `WrapperMode`
  (`.never`/`.onlyIfMultiple`/`.always`), `DestinationStrategy`
  (`.nextToArchive`/`.fixed(URL)`/`.askEachTime`), `openFolderAfter`,
  `moveToTrashAfter`. Дефолты совпадают с оригинальным Unarchiver
  (`.onlyIfMultiple`, `.nextToArchive`, `false`, `false`).

**Аддитивная правка `Newtua`:** `ExtractReport` получил публичный
`init` и `Equatable`, чтобы `JobState: Equatable` выводился
автоматически.

**Тесты:** 17 тестов в `NewTheUnarchiverTests` (4 TDD-минимум + 13
расширенных), все зелёные. Полный набор Swift Testing.

## 2026-06-23 — Stage 1: фаза ревью (шаги 7–10)

После прогона полного набора прошли три параллельных ревью-агента.
Принято к исправлению:
- Удалён шаблонный `NewTheUnarchiverTests.swift` (пустой `example()`
  от Xcode-шаблона).
- `recordProgress` теперь игнорирует запись, если состояние не
  `.running` — иначе поздний тик от движка перетёр бы финальное
  состояние.
- Удалён бесполезный тест `recordProgress_storesLatest` (проверял
  только nil-default; в комментарии была ссылка на следующий этап,
  что запрещено брифом).
- В `AppModel.enqueue` set активных URL теперь строится через
  `map(\.url)` вместо `map(\.url.standardizedFileURL)`: URL'ы
  хранятся уже стандартизованными, повторная нормализация лишняя.

**Зафиксированные дизайн-решения (без правок кода):**
- **Модель переходов разрешительная.** `JobState.canTransition(to:)`
  сейчас лишь проверяет `!isTerminal`. Валидность конкретных
  переходов — забота runner-а (Этап 2). Полная матрица переходов
  избыточна для модели без поведения.
- **`cancel()` на `.needsPassword` → сразу `.cancelled`.** Пользователь
  закрыл диалог пароля = отменил задачу. Cancellation token флипается,
  даже если фоновой операции нет — безопасно (Newtua-движок не запущен).
- **Дедуп строкозависим.** `URL.standardizedFileURL` нормализует только
  `.` и `..`. Не резолвит симлинки, не учитывает case-insensitive FS
  (APFS по умолчанию). Для v1 этого достаточно: дроп одного и того же
  файла дважды — единственный реальный сценарий дублирования.

**Отклонено:**
- Возврат `Bool`/`assertionFailure` из `updateState` — модель остаётся
  немой; вызывающий код (runner) сам отвечает за корректность.
- Переименование `canTransition(to:)` → `canLeave` — план явно
  использует терминологию "transition"; меняется только семантика.
- Извлечение тестовых хелперов в общий файл — тесты компактные,
  17 штук, абстракция преждевременна.

**Повторный прогон:** 17/17 в `NewTheUnarchiverTests` зелёные;
20/20 в Newtua-пакете зелёные.

## 2026-06-23 — Этап 2 завершён

Движок очереди (последовательная распаковка одной задачи за раз):
- `Engine/JobRunner.swift` — `@MainActor` обёртка над одним `ArchiveJob`.
  Держит личный `DispatchQueue(label: "newtua.job.<uuid>")`, на нём
  открывает `Archive` и зовёт sync `extract`. Прогресс прокачивается
  через `ProgressThrottle` (на той же queue), эмиты хопаются на main
  через `DispatchQueue.main.async`. На вход — `destination`,
  `ExtractionOptions`, опциональный `password`. На выход — `run() async`
  без бросков: все исходы (включая `.encrypted`/`.wrongPassword`/`.io`/
  `.cancelled`) попадают в `job.state`.
- `Engine/ProgressThrottle.swift` — буферизация тиков прогресса с двумя
  правилами коалесинга: (1) `started`/`finished` всегда эмитятся,
  (2) идентичные подряд значения (`==`) подавляются. Между ними —
  обычный rate-limit ~24 Гц через инжектируемое время для тестов.
- `Engine/QueueDriver.swift` — последовательный drain очереди по
  cursor-индексу: задачи, добавленные во время drain'а, подхватываются
  автоматически. Стадия 3 заменит этот драйвер планировщиком
  совместимости.

**Аддитивные правки `Newtua`:** у `Progress` появился публичный
memberwise `init` и `Equatable` — нужны для тестирования троттла и для
правила коалесинга «идентичный тик подавляем».

**Тесты:** 17 новых в `NewTheUnarchiverTests` (4 TDD-минимум + 13
расширенных). Полный набор приложения: 34/34 зелёные. Newtua-пакет:
20/20 зелёные. Сборка проекта через `xcodebuild test` — без ошибок.

## 2026-06-23 — Stage 2: фаза ревью (шаги 7–10)

Три параллельных ревью-агента (reuse / quality / efficiency).
Принято к исправлению:
- **Гонка в `ProgressThrottle`**: `feed` зовётся с job-queue, `flush()`
  — с main actor; класс non-Sendable, два потока на одних полях. Фикс
  — перенести `flush()` внутрь `queue.async` блока после `extract`,
  чтобы и feed, и flush шли с одной очереди.
- **No-op прогресс хопал на main**: `feed` теперь возвращает `nil`,
  если новое `Progress` равно последнему эмитнутому. Снижает работу в
  hot-path и подавляет лишние rerender'ы `@Observable`.
- **`QueueDriver.nextQueuedJob` стрингли-типизирован и O(n²)**: добавил
  `JobState.isQueued`; drain переведён на cursor-индекс, что заодно
  корректно подхватывает задачи, добавленные во время drain'а.
- **Narrative-комментарии удалены** («Stage 2 only», «per § 5.2»,
  «.always handled in stage 8», «stage 8 wires the strategy»). Оставлен
  WHY-комментарий про non-thread-safe throttle.
- **TestSupport-дубль** (с `bindings/swift/Tests/NewtuaTests/TestSupport.swift`)
  отмечен явным комментарием «keep in sync»; общий пакет — overkill для
  двух копий.

**Зафиксированные дизайн-решения (без правок кода):**
- **Async-API `Archive.extract` не используем в JobRunner.** Async-
  вариант обёртки хопает каждый тик прогресса на main automatically,
  что противоречит принятому в decisions.md решению (2026-06-22 —
  «троттлинг на стороне ArchiveJob перед хопом на @MainActor»). Поэтому
  JobRunner держит собственный sync-pipeline с троттлом до hop'a.
  Двойной DispatchQueue (Newtua-овский для async + JobRunner-овский для
  sync) принят как осознанная цена; lazy-вариант Newtua-queue был
  отклонён ещё в Stage 0.
- **`wrapperMode == .always` сейчас мапится так же, как `.onlyIfMultiple`**
  (оба → `wrapper: true`), потому что C-ABI не различает. Полноценное
  поведение «всегда оборачивать» — этап 8 (post-extract физическая
  обёртка либо расширение ABI). TODO висит здесь.
- **`defaultDestination` использует `nextToArchive`** независимо от
  `ExtractionOptions.destinationStrategy`. Полная стратегия (включая
  `.fixed`/`.askEachTime`) приходит в этап 8; до тех пор поле
  `destinationStrategy` сохраняется в модели, но не считывается
  драйвером.

**Отклонено:**
- Полностью переписать `JobRunner` на `Archive.extract(... async)` —
  см. дизайн-решение выше.
- Сделать `JobRunner` stateless с параметрами в `run()` — текущая форма
  читается лучше, без выгоды.
- Вынести `TestSupport` в общий target — overkill для двух копий.

**Повторный прогон:** 34/34 в `NewTheUnarchiverTests` зелёные;
20/20 в Newtua-пакете зелёные.

## 2026-06-23 — Этап 3 завершён

Умный планировщик параллели заменил последовательный `QueueDriver`:
- `Engine/VolumeProbe.swift` — протокол `VolumeProbing` (`isInternal`,
  `mediumType`) + `enum VolumeMediumType { ssd, hdd, unknown }` +
  `SystemVolumeProbe` (final class, кеш по mount-path через
  `OSAllocatedUnfairLock`).
- `Engine/CompatibilityPredicate.swift` — `struct PendingJob { job,
  destination }` и pure `areCompatible(_:_:probe:)`. Блокеры:
  совпадение `destination.standardizedFileURL.path`, awaiting password
  у любой стороны, не-internal / не-SSD исходник.
- `Engine/Scheduler.swift` — `@MainActor final class`. `maxParallel =
  max(1, min(cpuCount, 4))` (clamp от 0). Хранит активные слоты как
  `[UUID: ActiveSlot { pending, task }]`, методы `dispatch()` (запуск
  совместимых до заполнения слотов), `waitUntilQuiescent() async`
  (тесты/shutdown), `pickCompatibleQueuedJob() -> PendingJob?`
  (детерминистическое тестирование). Тест-хук `markActive(_:destination:)`.
- `ArchiveJob.defaultDestination: URL` — вынесен из `Scheduler` в
  `Domain/ArchiveJob.swift`, чтобы UI/Stage 8 переиспользовали без
  расхождений.
- `JobState.isAwaitingPassword` — новый хелпер для `CompatibilityPredicate`.
- `QueueDriver` удалён вместе со своими тестами; его инварианты
  покрыты `Stage3ExtendedTests` через `Scheduler.dispatch + waitUntilQuiescent`.

**Зафиксированные дизайн-решения:**
- **SSD-эвристика v1:** SystemVolumeProbe считает любой internal том
  `.ssd`, кроме случая когда `volumeLocalizedFormatDescription`
  содержит "Fusion" (легаси Intel Fusion drive → `.unknown` → serial).
  Полноценный IOKit + DiskArbitration probe — задача v1.1.
- **Сравнение destination через `.path`:** `URL.==` чувствительно к
  trailing slash; `URL(fileURLWithPath: "/tmp/x")` и
  `URL(.../x/y.zip).deletingLastPathComponent()` дают разные URL для
  одной директории. Сравниваем через `standardizedFileURL.path`.
- **`maxParallel` статический потолок:** соответствует решению из
  decisions.md (2026-06-22 «Параллельная распаковка»). Без динамики
  на Low Power Mode и т.п. — лишний шум, прирост сомнителен.
- **`markActive` оставлен как internal test hook:** видим только тест-таргету
  через `@testable`; production-views его не используют. Gate под
  `#if DEBUG` не делаем — overkill для одного типа в внутреннем модуле.

**Тесты:** 6 TDD-минимум + 11 расширенных = 17 новых в
`Stage3{,Extended}Tests`. Минус 3 удалённых QueueDriver-теста.
Полный набор приложения: 49/49 зелёные. Newtua-пакет: 20/20 зелёные.

## 2026-06-23 — Stage 3: фаза ревью (шаги 7–10)

Три параллельных ревью-агента. Принято к исправлению:
- **`defaultDestination` дублировался в Scheduler и нигде больше не жил**
  — вынесен в `ArchiveJob.defaultDestination`. Pick + launch теперь
  делят один источник через `PendingJob`.
- **`SystemVolumeProbe` без кеша** (план явно требовал «cache by mount
  path») — добавлен внутренний `[String: Reading]` под
  `OSAllocatedUnfairLock`. Ключ — `volumeURL.path`. Снимает O(N×M)
  syscall'ы при больших очередях.
- **Эвристика SSD не учитывала Intel Fusion** — добавлена проверка
  `volumeLocalizedFormatDescription` на «fusion», такие тома → `.unknown`
  (serial, безопасный fallback).
- **`areCompatible` 5 positional params** — заменено на `(PendingJob,
  PendingJob, probe)`. Call sites читаются лучше, pick/launch делят
  один объект.
- **`StubProbe` cross-file usage без документа** — добавлен
  one-line комментарий «shared with Stage3ExtendedTests».

**Отклонено:**
- Gate `markActive` под `#if DEBUG` — utility internal в test-target,
  не leak за пределы модуля; усложнение без выгоды.
- `cancelAll()` для shutdown — задача UI-слоя (Stage 4+), не Stage 3.
- Дополнительные allocations-микрооптимизации в `areCompatible` —
  после введения `PendingJob` destinations вычисляются один раз на
  кандидата; остальное — мизер.
- `waitUntilQuiescent` ratio — корректен под MainActor (ревью-агент
  сам подтвердил после анализа).

**Повторный прогон:** 49/49 в `NewTheUnarchiverTests` зелёные.

## 2026-06-23 — Этап 4 завершён

Главное окно очереди подключено. SwiftUI macOS 26+, без Combine, без
SwiftData. Решено идти по «варианту (б)»: тестируем извлекаемые куски
юнит-тестами Swift Testing, XCUI-smoke оставляем на следующий проход.

**Что появилось:**
- `Views/QueueWindow.swift` — корневой контент: список задач, drop-зона
  (`dropDestination(for: URL.self)`), пустое состояние с подсказкой,
  внутренний namespace `QueueWindowAccessibility` для window-ID и accessibility-id.
- `Views/JobRowView.swift` — строка задачи: иконка формата, имя,
  локализованный подзаголовок по виду состояния, либо детерминированный,
  либо неопределённый `ProgressView`, кнопка ×.
- `Views/JobRowDisplay.swift` — pure value-проекция `ArchiveJob` в поля
  строки (title / subtitleKind / progressFraction / showsCancelButton).
  `SubtitleKind` — enum, чтобы тесты были locale-independent.
- `Views/FormatIcon.swift` — иконка формата по расширению с whitelist
  через `UTType.conforms(to: .archive)` и MainActor-кэшем `[String: NSImage]`.
  Архивные расширения конечны, эвикция не нужна.
- `Views/QueueWindowVisibility.swift` — pure state-machine debounce-показа
  (`hidden / shown / pendingHide(deadline)`). С тестами, но **в окно не
  подключён** — см. следующее решение.
- `Localizable.xcstrings` — 12 ключей в RU+EN: заголовки, подзаголовки,
  подсказки, accessibility-метки.
- В `Domain/ArchiveJob.swift` появилось `displayName` и monotonicity-guard
  в `recordProgress` (не показываем «откат» прогресса внутри одной entry).
- В `Domain/AppModel.swift` появились (1) фильтр папок прямо в
  `enqueue(urls:)` — общий вход для drop, File ▸ Open…, double-click и
  (2) `cancel(_: ArchiveJob)`, инкапсулирующий «отменить, и если ещё не
  стартовала — удалить из очереди».
- App-сцена: `WindowGroup("queue.window.title", id: ...)` с
  `AppCoordinator` (хранит `AppModel` + `Scheduler`).

**Зафиксированные дизайн-решения:**
- **`QueueWindowVisibility` тестово готов, но не подключён к окну.** Окно
  пока всегда видно при пустой очереди (показывается empty-state с
  иконкой и подсказкой «Перетащите архивы сюда»). Авто-скрытие из
  decisions.md (2026-06-22 «Видимость окна очереди») реализовано на
  уровне state-machine, но для интеграции с SwiftUI Window/WindowGroup
  нужен always-on координатор (MenuBarExtra или скрытая сцена) с
  `openWindow`/`dismissWindow`. Это отдельная фасеточная задача — пока
  откладываем, контроллер с тестами не выбрасываем, чтобы при подключении
  на стадии 5 не переписывать.
- **XCUI-smoke отложен.** В `xcodebuild test` test-runner на этой машине
  не видит windows SwiftUI-приложения (window-attribute «Disabled»,
  пустой Element subtree), даже когда приложение реально запущено и
  отображает окно (проверено ручным `open -g`). Подозрение —
  TCC/permissions / Liquid Glass accessibility-bridge на macOS 26.5.1.
  Пока вместо XCUI-теста в `NewTheUnarchiverUITests.swift` лежит
  placeholder; на стадии 5+ вернёмся к этому, возможно после
  выдачи прав test-runner-у вручную.
- **Дроп URL → `AppModel.enqueue` сам отбрасывает папки.** Не view-layer,
  потому что File ▸ Open…, onOpenURLs и double-click будут читать тот же
  массив URL и должны фильтроваться по тому же правилу.
- **`FormatIcon` использует только `UTType.archive`-whitelist.** Раньше
  была проверка `conforms(to: .data)`, которая истинна почти для всего;
  заменена на `.archive`, неизвестные расширения получают fallback на
  системную иконку архива (визуально консистентный «generic archive»).
- **`@MainActor` на `QueueWindowVisibility`.** Несмотря на pure-state,
  держим на main — все потребители (SwiftUI views, `Task`-задержки) уже
  на main. Снятие изоляции дало бы микро-удобство тестам, но добавило
  бы хрупкости в продакшен.

**Тесты:** 8 TDD-минимум + 11 расширенных = 19 новых в
`Stage4{,Extended}Tests`. Полный набор приложения: 68/68 зелёные.
Newtua-пакет — без изменений, ранее 20/20. Сборка через
`BuildProject` — без ошибок.

## 2026-06-23 — Stage 4: фаза ревью (шаги 7–10)

Три параллельных ревью-агента (reuse / quality / efficiency). Принято
к исправлению:

- **`ArchiveJob.displayName`** — единая точка истины для имени файла,
  будет переиспользована в Stage 5+ (заголовки prompt, уведомления).
  `JobRowDisplay` теперь читает её, а не `url.lastPathComponent`.
- **Фильтр папок перенесён в `AppModel.enqueue`** — был в
  `QueueWindow.handleDrop`. Все будущие источники URL отбрасывают
  каталоги одинаково.
- **`AppModel.cancel(_:)`** — вынесена логика «отменить, и если задача
  ещё была `.queued` — удалить из очереди». UI больше не знает про
  состояния, просто зовёт `model.cancel(job)`.
- **`QueueWindowAccessibility` namespace** — собрал `windowID` и
  accessibility-IDs в одном месте, чтобы тесты и `openWindow(id:)`
  не разъезжались.
- **`@Bindable` снят с `QueueWindow.model`** — никаких `$model.prop`
  биндингов не было, `@Observable` достаточно для re-render.
- **Кэш `FormatIcon` по расширению** — `NSWorkspace.icon(for:)` бил в
  систему на каждом ре-рендере каждой строки (24 Гц прогресс × N строк
  → шум в системе на известный детерминированный ответ).
  Кэш `[String: NSImage]` под MainActor, эвикция не нужна — расширения
  конечны.
- **`FormatIcon` whitelist `UTType.archive`** — раньше пропускал почти
  всё через `conforms(to: .data)`.
- **`JobRowView` ProgressView склеен** — была двойная ветка
  determinate/indeterminate с пересекающимися условиями.
- **Narrative-комментарии вычищены** во всех новых файлах: ссылки на
  «Stage 2 / Stage 8», `decisions.md → Stage 4 risks`, «Stage 8 will layer
  …» и подобные. Оставил только timeless WHY.

**Отклонено:**
- Перенос `FormatIcon` из `Views/` в `Engine/Platform/` — преждевременно,
  пока единственный потребитель — `JobRowView`.
- Абстракция switch в `JobRowDisplay` через таблицу — семь строк
  читаются лучше, чем generic-обёртка.
- Расширение `Newtua.Progress.fraction: Double?` — пока один потребитель
  (`JobRowDisplay`), перенос в пакет ради будущих Stage 6+ опережает спрос.
- Снять `@MainActor` с `QueueWindowVisibility` — см. дизайн-решение выше.
- Дроп payload (`PasswordReason`, `ErrorCode`, `ExtractReport`) из
  `SubtitleKind` — нужен Stage 6+ для prompt'ов и сообщений об ошибках,
  тесты их уже валидируют.

**Повторный прогон:** 68/68 в `NewTheUnarchiverTests` зелёные;
сборка `BuildProject` — чистая.

## 2026-06-23 — App Sandbox выключен

При ручной проверке Stage 4 (drag-and-drop `tui.zip`) задача переходила
в `.succeeded`, но физической распаковки не было — записи блокировались
песочницей. Entitlements автоматически выставляли
`com.apple.security.app-sandbox = YES` + `user-selected.read-write`,
чего недостаточно для записи рядом с архивом по dropped URL (scope даётся
только на чтение самого файла).

**Решение:** в `Signing & Capabilities` удалена capability **App Sandbox**
(вручную через Xcode UI). Согласуется с уже принятым решением 2026-06-22
«security-scoped bookmarks не используем»: для v1 приложение не
sandbox-ится, distribution — вне Mac App Store.

**Что осталось:** при попытке записи в защищённые директории
(`~/Downloads/`, `~/Documents/`, `~/Desktop/`, `~/Pictures/`) macOS
по-прежнему показывает TCC-диалог. Сейчас текст диалога — дефолтный
системный; в Info.plist стоит добавить `NSDownloadsFolderUsageDescription`
и соседей с осмысленной фразой типа «NewTheUnarchiver хочет распаковать
архив в эту папку». Это пункт стадии 8 (post-extract actions/permissions),
не блокирует Stage 4.

## 2026-06-23 — Авто-удаление terminal-строк (1.2 сек)

После окончания задачи строка в очереди должна тихо исчезать, как в
оригинальном The Unarchiver. Реализовано:

- `AppModel.terminalDisplayDelay: TimeInterval?` — по умолчанию `nil`,
  то есть auto-removal выключен (Stage 1–3 тесты живут без правок,
  assertions на `app.queue` после `waitUntilQuiescent` продолжают работать).
- `AppCoordinator` в App-сцене явно создаёт `AppModel(terminalDisplayDelay: 1.2)`.
- `AppModel.handleTerminal(_ job:)` — после терминального state ставит
  `Task.sleep(for: delay)` и `remove(job)`. Удаление — fire-and-forget,
  не блокирует `Scheduler.waitUntilQuiescent`, поэтому race с тестами
  отсутствует.
- `Scheduler` дёргает `model.handleTerminal(pending.job)` ровно один раз
  после `runner.run()`.

**Почему 1.2 сек:** достаточно увидеть «Готово / Ошибка / Отменено» как
подтверждение, мало чтобы накапливать визуальный шум в очереди.

**Тесты:** 2 новых в `Stage4ExtendedTests` (срабатывание с delay, no-op
при `nil`). Полный набор: 70/70 зелёные.

## 2026-06-23 — Общий прогресс по архиву вместо «бара на каждый файл»

При ручной проверке Stage 4 стало видно, что прогресс-бар в строке
очереди пересчитывается **для каждой entry внутри архива**
(`bytesWritten / entrySize`). На архиве из десятков файлов бар прыгает
0→100 десятки раз — выглядит «сломанным». Поведение оригинала и
устоявшихся macOS-приложений (Finder, Safari, Music) — один бар на весь
процесс + текст пути.

**Сделано:**
- `ArchiveJob.overallFraction: Double?` — наблюдаемое 0…1 на весь архив,
  `nil` пока entries неизвестны (фолбэк на indeterminate-спиннер).
- `ArchiveJob.setEntries(sizes:)` — `JobRunner` зовёт один раз после
  `Archive(path:)`, передавая `archive.entries().map(\.size)`. Внутри
  считаются кумулятивные оффсеты по entry, сумма становится `totalBytes`.
- `recordProgress` дополнительно вычисляет `overallFraction =
  min(1.0, (offsets[index] + bytesWritten) / totalBytes)`. Монотонный
  guard на случай stale-тика из прошлой entry.
- `JobRowDisplay.progressFraction` теперь читает `job.overallFraction`.
- Составной бар (общий + per-entry) обсуждался и отклонён: per-entry
  на типичных архивах из мелких файлов «пульсирует» 0→100 несколько раз
  в секунду — визуальный шум, не информация.

**Тесты:** 3 новых в `Stage4ExtendedTests` (аккумуляция через несколько
entries, монотонность, `nil` пока `setEntries` не вызван). Обновлены
`display_running_withProgress` и `display_running_unknownSize_noFraction`
под новый источник fraction.

## 2026-06-23 — Параллель: блокер «общая папка назначения» снят

Ручная проверка на M1 Air показала: пользователь дропает несколько
архивов из `~/Downloads/`, все ждут серийно. По прежнему предикату
`areCompatible` блокировал параллель при совпадении
`destination.standardizedFileURL.path`. На практике этот блокер
избыточен — два разных архива пишут в разные пути (`a.zip → a/`,
`b.zip → b/`); APFS переживает параллельные записи в одну директорию
без проблем; коллизия имён внутри двух архивов крайне маловероятна.

**Сделано:**
- В `CompatibilityPredicate.areCompatible` убрана проверка
  `destinationKey`. Остались актуальные блокеры: внешний/HDD-том,
  ожидание пароля. `PendingJob.destinationKey` удалён за ненадобностью.
- `Stage3Tests.predicate_blocksParallel_ifSameDestination` →
  `predicate_allowsParallel_ifSameDestination`.
- `Stage3ExtendedTests.predicate_destinationStandardization` удалён
  (более не описывает поведение).
- `Stage3ExtendedTests.scheduler_pickCompatible_noneAvailable`
  перепиcан: вместо общей папки блокер ставится через `.needsPassword`.

**Баг, всплывший при снятии блокера:** `Scheduler.dispatch` крутился в
бесконечном цикле. `pickCompatibleQueuedJob` сразу после `launch`
находил **ту же** задачу (Task ещё не успел переключить state в
`.running`, поэтому она и `.queued`, и в `active`). Старый блокер по
dest неявно отсекал «себя с собой». Фикс — явный фильтр по `active.keys`
в `pickCompatibleQueuedJob`.

**Тесты:** полный набор 72/72 зелёные после фикса. Ручная проверка
параллели на M1 Air — следующий шаг.

## 2026-06-23 — Тайм-ауты для тестов

Несколько раз приходилось убивать висевшие `xcodebuild test`-сессии
вручную (приложение нагревало CPU без прогресса). Чтобы Claude мог
гонять тесты автономно:

- Все вызовы `xcodebuild test` идут с флагами
  `-test-timeouts-enabled YES -default-test-execution-time-allowance 30
  -maximum-test-execution-time-allowance 60` — каждый тест получает
  60-секундный «потолок», после которого test-runner убивает процесс и
  репортит фейл, остальная сюита продолжает.
- Параллельный запуск тестов отключён (`-parallel-testing-enabled NO`):
  под нагрузкой MainActor-suite-ы упирались в неявные ожидания друг
  друга. Серийный прогон стабилен.
- Перед/после каждого прогона — `killall -9 NewTheUnarchiver xcodebuild
  xctest` для гарантии отсутствия орфан-процессов.

Эти флаги работают без правок `.xcscheme` / создания `.xctestplan` —
xcodebuild уважает их напрямую.

## 2026-06-23 — Этап 6 завершён

Inline-блоки запроса пароля и выбора кодировки в строке очереди.

**Что появилось:**
- `Domain/ArchiveJob.swift` — поля `pendingPassword: String?` и
  `pendingEncoding: String?` плюс `attachPendingPassword/Encoding(_:)`.
  Одноразовые «карманы» для значений, введённых пользователем в inline-форме;
  `JobRunner` подхватывает их на следующем запуске и фолбэчит на
  `AppModel.sharedPassword`.
- `Engine/Scheduler.swift` — `submitPassword(_:applyToAll:for:)` и
  `submitEncoding(_:for:)`. Кладут значение, переводят задачу обратно
  в `.queued`, дёргают `dispatch()`.
- `Engine/JobRunner.swift` — конструктор принимает `encoding: String?`,
  пробрасывает в `Archive(path:, password:, encoding:)`.
- `Engine/EncodingPromptDebounce.swift` — чистая state-machine 200 мс
  для предпросмотра кодировки. По паттерну совпадает с
  `QueueWindowVisibility` (Stage 4).
- `Engine/EncodingPreviewer.swift` — единственная точка открытия архива
  ради preview первого ненулевого пути. Обходит `entry(at:)` без
  материализации полного `[Entry]`. View не импортирует `Newtua`.
- `Engine/SupportedEncodings.swift` — статический список кодировок:
  auto / UTF-8 / Cyrillic (cp1251, cp866) / Western / Central European /
  Shift JIS / EUC-JP / GBK / Big5 / EUC-KR. Лейблы — WHATWG-идентификаторы
  для `encoding_rs`, имена строк — ключи в Catalog.
- `Views/PasswordPromptForm.swift` — `SecureField` + чекбокс «Apply to All» +
  `Continue`. На `.wrongPassword` — красная подсказка над полем.
- `Views/EncodingPromptForm.swift` — `Picker` с `String?`-тэгами +
  живой `Result: <первое имя>` под ним. Кнопка `Continue` отдаёт выбор
  в `scheduler.submitEncoding`.
- `Views/JobRowView.swift` — `switch` по `subtitleKind` для accessory
  (вместо трёх `if case`); параметры переехали на прямые
  `model: AppModel` + `scheduler: Scheduler` (по Stage 4-паттерну, без
  closure-проброса). Pass-through-методы из `AppCoordinator` удалены.
- `Localizable.xcstrings` — 18 новых ключей (RU+EN) для всех новых
  лейблов / кнопок / плейсхолдеров / подсказок.

**Зафиксированные дизайн-решения:**
- **`String?` через Optional-тэги Picker, без sentinel.** Первая
  версия использовала `id = label ?? ""`, что повторяло ошибку
  Stage 0 (stringly-typed `kind: String`). Заменено на `Picker(selection:
  $selected as String?)` с `.tag(enc.label)`, где `enc.label: String?`.
  Auto-detect — это `nil`, а не пустая строка.
- **Открытие `Archive` ради preview — только в `Engine/EncodingPreviewer`,
  не в View.** View не импортирует `Newtua`. Соблюдает §0 брифа
  (`apps/macos/CLAUDE.md`): «никакой логики архивов в Swift-слое».
- **`Scheduler` передаётся в View напрямую, как `AppModel`.** Stage 4
  установил паттерн «view знает model и зовёт `model.cancel(job)`»;
  здесь продолжаем — view знает scheduler и зовёт
  `scheduler.submitPassword/submitEncoding`. Closure-проброс на 4 уровня
  (`App` → `QueueWindow` → `JobRowView` → форма) свернули в один —
  closure остался только у самой формы (на `Continue`).
- **`pendingPassword/pendingEncoding` отдельно от `JobState`.** Альтернатива
  (зашить payload в `.queued(pending: …)`) была отклонена: текущая форма
  читается лучше, разделение «состояние UI» и «hand-off slot для runner»
  явное. Если будет третий вид pending — пересмотрим.
- **`Onappear` запускает preview сразу.** Это не дубль работы движка:
  пользователь попал в `.needsEncoding` именно потому, что авто-детект
  не подошёл (или подошёл частично). Преview с auto-detect снова —
  чтобы показать в форме, как именно сейчас декодируются имена.
- **`pickerStyle(.menu)` вместо segmented/radial.** Список из 12 кодировок
  — для popup menu естественный размер; стилизация Liquid Glass на
  `.menu` рендерится сама.
- **`Apply to All` не пишет на диск.** `AppModel.sharedPassword` живёт
  только в памяти и сбрасывается на выходе из приложения. Соответствует
  решению 2026-06-22 «Пароль и кодировка».

**Тесты:** 4 TDD-минимум (`Stage6Tests`) + 13 расширенных
(`Stage6ExtendedTests`). Полный набор приложения: 94/94 зелёные. Сборка
через `BuildProject` — чисто.

## 2026-06-23 — Stage 6: фаза ревью (шаги 7–10)

Три параллельных ревью-агента (reuse / quality / efficiency). Принято
к исправлению:

- **`""` как sentinel для nil-кодировки.** Stringly-typed повтор ошибки
  Stage 0. Заменено на `Picker(selection: $selected as String?)` с
  Optional-тэгами; `SupportedEncoding` больше не `Identifiable` —
  `ForEach` через `id: \.label`.
- **Открытие `Archive` из View.** `EncodingPromptForm.fetchPreview`
  вызывал `Archive(path:, encoding:)` в самом view, нарушая §0 брифа.
  Логика переехала в `Engine/EncodingPreviewer` — единственный потребитель
  `import Newtua` среди новых файлов Stage 6.
- **Полный `entries()` ради первого имени.** Заменено на обход
  `archive.entry(at: i)` в цикле — для архива на 50 тыс. файлов это
  десятки тысяч аллокаций пути впустую. Цикл также проверяет
  `Task.isCancelled` между шагами.
- **Отсутствие `Task.isCancelled` перед `Archive(path:)`** в детачнутой
  задаче. Добавлены проверки до и после открытия — чтобы быстрая
  смена пяти кодировок не оставляла 4 завершённых open в фоне.
- **Closure-проброс на 4 уровня.** `App → coordinator.submitPassword →
  QueueWindow.onSubmitPassword → JobRowView.onSubmitPassword → форма`.
  Свернули: `Scheduler` передаётся в `QueueWindow` и `JobRowView`
  напрямую (по аналогии с `model`); формы остались с одним closure
  на `Continue`. `AppCoordinator.submitPassword/submitEncoding` удалены
  как мёртвые pass-through.
- **3 `if case` в `JobRowView.body` → один `switch`.** Accessory-секция
  (progress / password form / encoding form) теперь читается единым
  паттерн-матчингом на `subtitleKind`.
- **Narrative-комментарий «keep that in sync»** в `EncodingPromptForm`
  исчез — sentinel заменён типом, инвариант кодируется в `String?`,
  а не в комментарии.
- **`defaultValue: "Password"` в `SecureField`** — лишний параметр
  (Catalog всё равно перекрывает). Удалён для консистентности.

**Отклонено:**
- **`@State` mutating struct (`EncodingPromptDebounce`)** — агент сам
  написал «not a bug, designed-for». SwiftUI хранит `@State` в reference-
  backed storage, mutating-метод через keypath работает.
- **`pendingPassword/pendingEncoding` ↔ `JobState` payload** —
  архитектурная альтернатива (зашить в `.queued`), агент пометил
  «обсудить, не баг». Для v1 текущая форма чище.
- **`PromptRow<Control>` shared abstraction** для двух форм —
  агент сам пишет «factor when third appears».
- **Onappear-fix (skip первый preview)** — UX-решение: пользователь
  попал в форму потому, что автодетект не сработал, и первое имя
  с автодетектом — ровно та информация, которую он хочет видеть.
- **`JobRunner.entries().map(\.size)`** — нерегресс, помечено как
  debt-note (для очень больших архивов).

**Повторный прогон:** 94/94 в `NewTheUnarchiverTests` зелёные;
сборка `BuildProject` — чистая.

## 2026-06-23 — Stage 6 hotfix: контракт `Encrypted`/`WrongPassword` в движке

Ручная проверка Stage 6 на свежесозданных `secret-{1,2,3}.zip` (ZipCrypto,
`zip -P pw …`) выявила, что приложение не показывает запрос пароля и
«успешно» создаёт пустые файлы. Изначальный диагноз — баг в Swift или
ZIP-handler-е — оказался неверным.

**Реальная причина:** общая orchestration `extract_all` в `newtua-core`
проглатывала per-entry-ошибки шифрования в `ExtractReport.failed` и
возвращала `Ok` для **всех форматов** (ZIP, content-encrypted 7z, RAR).
7z с header-encryption (`-mhe=on`) бросал `.Encrypted` ещё на `open()` —
это поведение и было моим (неверным) reference-контрактом.

**Что починили в движке** (коммиты `ec60059..e312c8b` на ветке `macapp`,
сделано Rust-агентом):
- Новый метод `ArchiveReader::verify_password(&mut self)` (дефолт — `Ok`,
  реализации в ZIP/7z/RAR; no-op для tar/ar/cab/gzip).
- `extract_all` вызывает `verify_password()` **один раз** до создания
  файлов. Без пароля или с неверным — `Err(Encrypted/WrongPassword)` на
  верхнем уровне, **ничего не пишется на диск**.
- ABI `NtuaStatus` не менялся, `newtua.h` не менялся. C-обёртка и
  `bindings/swift/Sources/Newtua/` без правок.

**Что это даёт GUI без единой Swift-правки:**
- `JobRunner` уже корректно ловит `.encrypted`/`.wrongPassword` в
  `catch let err as NewtuaError` (это было сделано ещё в Stage 2).
  Раньше ветка срабатывала только на header-encrypted 7z; теперь
  срабатывает и на ZipCrypto-ZIP, и на content-encrypted 7z, и на RAR.

**Контракт, на который мы теперь опираемся:**
- `ntua_open(path)` **без пароля** на ZipCrypto-ZIP / content-encrypted
  7z — **успешно**. `list`/`entries` работают, `Entry.isEncrypted` — флаг.
  Это намеренно — позволяет показать содержимое **до** запроса пароля.
- `ntua_open(path)` на header-encrypted 7z / RAR — `Encrypted` /
  `WrongPassword` (нельзя даже залистить без пароля).
- `ntua_extract(...)` без правильного пароля по любому encrypted-архиву
  — `Encrypted` или `WrongPassword` на верхнем уровне. Ничего на диск.
- `Ok` с `report.failed > 0` теперь означает **только** реальные
  per-entry проблемы (zip-slip, отказ на write и т.п.), **не** auth.

**Чего больше НЕ делаем (специально, чтобы не было соблазна):**
- **Не добавляем pre-check `entries.any(\.isEncrypted)` в Swift.**
  Это нарушение Prime Directive (§0 брифа): архивная логика — в движке.
- **Не парсим `report.failed` как сигнал «нужен пароль».** После фикса
  это не работает: auth-ошибки приходят как `Err`, а не как
  `Ok + failed`.
- **Не gate-им `list` на пароле.** Listing без пароля — feature.

**Известные ограничения движка** (для GUI-тестов и фикстур):
- **Content-encrypted 7z + WRONG password** в `sevenz-rust2` ненадёжен —
  может вернуть мусорные байты вместо ошибки. **Для GUI-фикстур
  использовать только `-mhe=on` (header-encrypted).** Существующая
  `secret.7z` в `crates/newtua-core/tests/fixtures/` — header-encrypted,
  это правильно.
- **ZipCrypto wrong password** имеет ~1/256 false-accept (известное
  свойство формата; The Unarchiver такой же). Для надёжного теста
  «wrong password» брать AES-encrypted ZIP или header-encrypted 7z.

**Проверка:**
- CLI на `secret-{1,2,3}.zip`: без пароля → «архив зашифрован», ничего
  не пишется; с неверным → «неверный пароль», ничего не пишется; с
  правильным → распаковывается. `list` без пароля — работает.
- 94/94 в `NewTheUnarchiverTests` зелёные после пересборки lib.
- Ручная проверка GUI на тех же файлах — теперь должна показывать
  inline-форму пароля.

**Handoff-документ** от Rust-агента —
`docs/handoff-2026-06-23-encrypted-extract.md`. Источник правды по
контракту.

## 2026-06-23 — Stage 6 UX-фикс: Apply-to-All fan-out и shared-vs-explicit

Ручная проверка с тремя ZipCrypto-архивами обнажила два UX-бага после
того, как engine-контракт заработал:

1. **Apply-to-All не догонял параллельно ждущие.** Два архива стартанули
   одновременно и оба провалились в `.needsPassword(.encrypted)`.
   Пользователь ввёл пароль с «Для всех» в первой строке — `sharedPassword`
   проставился, первая задача распакована, **но вторая** так и сидела
   ждать ручного ввода. Спец говорит «применяется к следующим в очереди» —
   так и должно быть, но «следующие» включает и тех, кто **сейчас**
   ждёт пароля, не только будущие.
2. **Третий архив сразу пишет «Пароль не подошёл», хотя не вводился.**
   После Apply-to-All движок тихо пробовал `sharedPassword` на новом
   архиве, получал `WrongPassword`, и UI показывал красный хинт
   «Пароль не подошёл — попробуйте ещё раз». Пользователь не понимал
   откуда «не подошёл», если он ничего не вводил.

**Что починили:**
- **`Scheduler.submitPassword(applyToAll: true)`** теперь после установки
  `sharedPassword` проходит по `model.queue` и для каждой задачи в
  `state.isAwaitingPassword` (любой `PasswordReason`) вызывает
  `requeue(withPassword:)`. Это «фан-аут»: один Apply-to-All зачинает все
  параллельно ждущие задачи с тем же паролем.
- **Новый кейс `PasswordReason.sharedDidNotMatch`** разделяет два
  сценария:
  - `.wrongPassword` — пользователь сам ввёл пароль, тот не подошёл.
    Красный хинт «Пароль не подошёл — попробуйте ещё раз».
  - `.sharedDidNotMatch` — runner молча попробовал запомненный
    `sharedPassword`, тот не подошёл. Нейтральный хинт «Запомненный
    пароль не подошёл к этому архиву, введите его пароль».
- **`JobRunner.passwordIsShared: Bool`** — новый init-параметр. Scheduler
  в `launch` выставляет `passwordIsShared = explicit == nil &&
  resolvedPassword != nil`. На `WrongPassword` от движка runner выбирает
  reason по этому флагу.
- **`ArchiveJob.requeue(withPassword:)`/`requeue(withEncoding:)`** —
  единый паттерн «attach pending + перевести в .queued», вынесенный из
  Scheduler (был дубль в submitPassword/submitEncoding × двух местах).
- **`attachPendingPassword/Encoding`** теперь idempotent — guard на
  равенство значения, как в `recordProgress`. Двойной Apply-to-All с
  тем же паролем не шлёт лишних `@Observable`-уведомлений.

**Зафиксированные дизайн-решения:**
- **`passwordIsShared` живёт на `JobRunner`, не на `Scheduler`.** Ревью
  предлагал переписывать state из Scheduler после Task-завершения, но
  это нарушает инкапсуляцию (runner отвечает за state как сейчас,
  scheduler — за orchestration). Флаг — это факт о входе runner-а
  («мы тебя запустили с тихим shared»), а не UX-концепция.
- **`""`-pendingPassword не отсекается на типовом уровне.** UI блокирует
  `disabled(password.isEmpty)`, до runner-а пустой пароль не дойдёт.
  Защита от impossible state — over-engineering.
- **Snapshot `model.queue` перед итерацией не нужен.** MainActor +
  `@Observable` уведомления не синхронны во время фрейма — гонок не будет.
- **«Перезапись sharedPassword новым Apply-to-All — намеренно.»**
  Пользователь явно сказал «теперь этот пароль для всего» — старый
  забывается, поведение совпадает с оригиналом The Unarchiver.

**Тесты:** 9 в `Stage6HotfixTests` (3 TDD-минимум + 6 extended). Полный
набор `NewTheUnarchiverTests`: **106/106 зелёные** после ревью-фиксов.

**Ревью-находки отклонены:**
- Защита от orphan-job (`precondition(model.queue.contains(job))`) —
  по архитектуре не может случиться (`submitPassword` зовётся из
  `JobRowView`, который держит job из `model.queue`).
- Доп. тест на «running при Apply-to-All → sharedDidNotMatch через
  естественный flow» — уже покрыт сочетанием двух существующих тестов
  (sharedPassword выставляется + sharedWrongPassword → sharedDidNotMatch).
- Computed property `hint: (Key, Color)?` вместо switch в
  `PasswordPromptForm` — стиль, не качество.

## 2026-06-23 — Этап 7 завершён (Preferences: три вкладки)

Окно Preferences подключено через SwiftUI-сцену `Settings { ... }` — ⌘,
открывает его. Три вкладки в стиле оригинального The Unarchiver:

**Archive Formats** — список поддерживаемых форматов с реальной
ассоциацией через Launch Services:
- `Settings/FileAssociationsService.swift` — протокол
  (`defaultHandler(forUTI:)`, `setDefaultHandler(_:forUTI:)`) + реализация
  `LaunchServicesFileAssociations` поверх
  `LSCopyDefaultRoleHandlerForContentType` /
  `LSSetDefaultRoleHandlerForContentType`. Без entitlements, без Sandbox.
- `Settings/ArchiveFormatsModel.swift` — `@MainActor @Observable` модель
  со списком строк `Row { format, currentHandler, isOurApp, handlerDisplay }`.
  `HandlerDisplay` (иконка + локализованное имя приложения) резолвится один
  раз во время `refresh()` и кэшируется на `Row` — иначе SwiftUI дёргал
  бы `NSWorkspace.urlForApplication` на каждом ре-рендере.
- `Settings/ArchiveFormatsTab.swift` — большая кнопка «использовать
  NewTheUnarchiver для всех форматов» + список с кнопками «Назначить»
  per row + footer-refresh. Ошибки `LSSetDefault…` показываются в
  стандартном `Alert`, не глотаются.
- `Engine/SupportedFormats.swift` расширен: добавлена `struct Format
  { utiIdentifier, extensions, displayNameKey }`. `fileExtensions` и
  `utTypes` стали `static let`, материализованными из `formats` один раз.

**Extraction** — UI на `AppModel.extractionOptions`. Радиокнопки
destination (`nextToArchive` / `fixed(URL)` / `askEachTime`), радиокнопки
wrapper (`never` / `onlyIfMultiple` / `always`), два toggle
(`openFolderAfter`, `moveToTrashAfter`). Для `fixed` — пикер папки через
`NSOpenPanel`.

**Advanced** — `Picker` глобальной `defaultEncoding` поверх существующего
`SupportedEncodings.all` (тот же список, что и в inline-форме Этапа 6).
`Scheduler.launch` теперь делает `pendingEncoding ?? defaultEncoding` —
per-job переопределение перекрывает глобальный.

**Персистентность (UserDefaults):**
- `Domain/ExtractionOptions.swift` — `Codable`, плюс новое поле
  `defaultEncoding: String?`.
- `Domain/AppModel.swift` — `init(defaults: UserDefaults = .standard)`,
  загрузка из ключа `newtua.extractionOptions` на init, `didSet`
  на `extractionOptions` пишет JSON обратно. `Equatable`-guard в `didSet`
  гарантирует «identity write → no-op». Битый JSON → молча fallback на
  дефолты (не падаем).
- Тестируем через изолированные `UserDefaults(suiteName: UUID())`
  суиты с `defer { iso.teardown() }` — `.standard` в тестах не трогаем.

**Зафиксированные дизайн-решения:**
- **Tab 1 не лжёт пользователю.** Никаких «галочек-обманок» —
  кнопки реально дёргают Launch Services. То, что Quick Look не показывает
  «их я тоже умею» — пользователь видит весь список форматов с
  актуальным состоянием.
- **Tab 1 без UserDefaults.** Источник истины — Launch Services.
  Преимущество: если пользователь поменял ассоциацию через Finder,
  следующее открытие Preferences (с `onAppear { model.refresh() }`)
  покажет актуальное состояние без рассинхронизации.
- **`ArchiveFormatsModel` владеется `AppCoordinator`**, не view. SwiftUI
  при переключении вкладок Settings не пересоздаёт модель, не делает
  лишних Launch Services-сканов. View просто читает `model.rows`.
- **`fileAssociations` сервис не светится в публичном API
  координатора.** Он локально в `AppCoordinator.init` создаёт
  `LaunchServicesFileAssociations()` и передаёт в `ArchiveFormatsModel`.
  Дальше View оперирует только моделью.
- **`destinationStrategy = .fixed(URL)` UI:** при выборе радио без
  ранее запомненного URL подставляем `~/Downloads/`. Пикер папки
  через `NSOpenPanel` показывает текущий URL как стартовый.
  Security-scoped bookmarks не используем (решение 2026-06-22).
- **`.fixed(URL)` и `askEachTime` НЕ ПРИМЕНЯЮТСЯ к фактической
  распаковке в Этапе 7.** UI и персистентность — есть, чтение этих полей
  `JobRunner`-ом — Этап 8 (post-actions + destination strategy
  одновременно). Сейчас `defaultDestination` всё ещё `nextToArchive`.

**Тесты:** Stage 7 — 22 теста (8 TDD-min + 10 extended для Tab 1,
7 для Tab 2 включая Codable round-trip, defaults match original,
персистентность через UserDefaults, fallback на корраптед JSON;
7 для Tab 3 включая два теста `Scheduler.resolvedEncoding` /
`resolvedPassword`). Полный набор: **138/138 зелёные**.

## 2026-06-23 — Stage 7: фаза ревью (шаги 7–10)

Три параллельных ревью-агента. Принято к исправлению:

- **`HandlerDisplay.resolve` дёргал `NSWorkspace.urlForApplication` /
  `NSWorkspace.icon` / `FileManager.displayName` из `body` каждого
  `ArchiveFormatRow`** — для 7 форматов = до 21 syscall на ре-рендер.
  Резолвится теперь один раз в `ArchiveFormatsModel.refresh()` и
  кэшируется в `Row.handlerDisplay: HandlerDisplay?`. Row потерял
  `Equatable` (NSImage не Equatable; тесты сравнивают поля).
- **`SupportedFormats.fileExtensions` и `utTypes` были computed
  properties** — `flatMap`/`compactMap` на каждом обращении, включая
  hot-path `fileImporter`. Вернули `static let`.
- **`ArchiveFormatsModel` владелась view через `@State` в `init`** —
  при каждом переключении вкладок Settings создавалась новая инстанция
  с фоновым `refresh()`. Поднята в `AppCoordinator`, ArchiveFormatsTab
  принимает её как `let` параметр. `onAppear { model.refresh() }`
  обеспечивает свежесть при возврате на вкладку.
- **`fileAssociations` пробрасывался через три уровня** (`App` →
  `SettingsScene` → `ArchiveFormatsTab`). Свернулось вместе с пунктом
  выше: координатор создаёт `LaunchServicesFileAssociations()` локально,
  владеет `ArchiveFormatsModel`. Сервис как stored property снят.
- **`try? model.setAsDefaultForAll()` молча глотал ошибку Launch
  Services.** Теперь оборачивается в `runWithErrorAlert { try ... }`
  и показывается через `.alert(item:)`. Пользователь видит, когда
  ассоциация не применилась.
- **`StubFileAssociationsService` в `Stage7Tests.swift` + `ThrowingStub`
  в `Stage7ExtendedTests.swift`** были двумя похожими стабами. Слиты
  в один — `StubFileAssociationsService` в `TestSupport.swift` с
  опциональным `shouldThrowOnSet` флажком.
- **`TestSupport.removeIsolatedDefaults` через KVC ключ
  `"NSUserDefaultsSuiteName"`** — KVC-доступ к этому полю не работает
  на современной macOS, dead branch. Refactor:
  `TestSupport.isolatedDefaults()` возвращает
  `IsolatedDefaults { defaults, teardown }`-структуру, `teardown`
  — closure, знающий suite name.
- **`Picker("", selection: ...)` создавал пустой ключ `""` в
  `Localizable.xcstrings`** при автосканировании Xcode. Заменено на
  `Picker(selection: ...) { ... } label: { EmptyView() }`. Пустая
  запись удалена из каталога.
- **`.tag(enc.label as String?)` redundant cast** — `SupportedEncoding.label`
  и так `String?`. Снят.
- **`currentFixedURL()` хелпер в `ExtractionTab`** дублировал
  `if case .fixed(let url) = ...` ещё в двух местах. Inline'нут;
  пикер папки и binding читают strategy напрямую.
- **Stage-narrative-комментарии** в `ExtractionTab`, `AdvancedTab`,
  `ArchiveFormatsModel`, `AppModel.extractionOptionsKey`,
  `ExtractionOptions` — упоминания «UI-only — Stage 8 wires…»,
  «decisions.md, 2026-06-23 Stage 1», «v1 hosts only…» удалены.
  Доки описывают контракт, не таймлайн.

**Отклонено:**
- **`destinationKindBinding` свести в computed-extension
  на `DestinationStrategy`** — потребовало бы пробрасывать
  `defaultFolder()` (FileManager) в модель. Текущая форма изолирует
  view-логику в view-слое.
- **`didSet` на `extractionOptions` пишет в UserDefaults на каждый
  set** — `Equatable`-guard уже отсекает identity writes. Будущий
  TextField внутри struct сейчас не планируется.
- **`HStack { Button; Spacer() }` для left-align** — две строки,
  читается так же, как `.frame(maxWidth: .infinity, alignment: .leading)`.
- **`Scheduler.resolvedPassword/Encoding` internal для тестов —
  «leaky visibility»** — паттерн уже установлен Stage 3
  (`pickCompatibleQueuedJob`). Симметрия сильнее микро-инкапсуляции.
- **`HandlerDisplay` в отдельном файле** — он остался в
  `ArchiveFormatsModel.swift`, потому что используется только моделью
  и тесно с ней связан. Отдельный файл — overkill для 15 строк.

**Повторный прогон:** 138/138 в `NewTheUnarchiverTests` зелёные;
сборка `BuildProject` — без ошибок; `XcodeListNavigatorIssues` по
`Settings/` — пусто.

## 2026-06-23 — Дыра в Этапе 6: `.needsEncoding` недостижим в продакшене

При триаже багов после Этапа 7 обнаружено, что состояние
`JobState.needsEncoding(currentEncoding:)` нигде в продакшен-коде не
выставляется. `JobRunner.run()` его не использует (там только пароль),
никакой UI-жест тоже не переключает задачу в это состояние.

Что построено в Этапе 6 и **работает в тестах**, но **не достижимо
пользователем**:
- `EncodingPromptForm` (View с picker + live preview)
- `EncodingPreviewer` (открытие архива под кандидатом-кодировкой)
- `EncodingPromptDebounce` (200 мс throttle на смену кодировки)
- 12 строк локализации `job.encoding.*`

Причина — Newtua-движок не возвращает сигнал «имена выглядят
подозрительно, спросите пользователя». Открытие архива всегда
«успешно» (с автодетектом или явной кодировкой), без вопросов наверх.

**Текущее последствие для пользователя:** единственный способ задать
кодировку — глобальный `defaultEncoding` во вкладке Advanced (Этап 7).
Если задана конкретная кодировка — движок не делает автодетект для
всех архивов. По умолчанию (`nil` / «Определить автоматически») —
движок выбирает сам.

**Подсказка во вкладке Advanced (`settings.advanced.encoding.hint`)
переписана честно**: «Pick a specific encoding only if you always work
with legacy archives in the same one. It replaces the engine's
automatic detection for every archive.»

**Что НЕ делаем сейчас:**
- Не удаляем код inline-формы — пригодится, когда триггер появится.
- Не удаляем вкладку Advanced — это единственный способ для
  пользователя переопределить кодировку.
- Не дефолтим в UTF-8 — это сломало бы автодетект для легасийных
  архивов без user-recovery path.

**Открытый пункт на потом:** добавить триггер для inline-формы.
Варианты:
1. Кнопка/контекстное меню «Re-extract with encoding…» на терминальной
   строке успешной распаковки — пользователь видит mojibake-имена в
   Finder, кликает, выбирает кодировку, распаковка повторяется в новую
   подпапку.
2. Расширить Newtua-ABI: при подозрительном автодетекте возвращать
   код `AmbiguousEncoding` — runner ловит его и переводит задачу в
   `.needsEncoding`. Требует Rust-работы.

Решение по триггеру — отдельный этап после v1, не блокирует релиз.

## 2026-06-23 — Хотфикс: cancel из `.needsPassword`/`.needsEncoding`

Ручная проверка Этапа 7 показала: при нажатии × на задаче, ждущей
пароль (или кодировку), строка очереди не удалялась. Причина в
`AppModel.cancel(_:)`:

- Для `.queued` — `remove(job)` сразу.
- Для `.running` — `handleTerminal` вызывался планировщиком,
  когда runner отрабатывал.
- Для `.needsPassword`/`.needsEncoding` — runner уже завершился ранее
  (после первого отказа движка по паролю), его `Task` отработал и вызвал
  `handleTerminal` один раз тогда, когда состояние было `.needsPassword`
  (не terminal), значит ничего не запланировалось. После cancel состояние
  становилось `.cancelled`, но второго `handleTerminal` уже не было —
  строка висела вечно.

**Фикс:** `AppModel.cancel(_:)` для non-queued случая всегда дёргает
`handleTerminal(job)`. Идемпотентность обеспечена двумя способами:
`remove(_:)` — `removeAll{ id == }` (no-op при повторе), плюс
`handleTerminal` теперь проверяет `queue.contains(...)` ДО запуска
sleep-таска — чтобы повторный вызов после уже произошедшего удаления
не плодил лишних Task'ов.

**Тесты:** 4 в `Stage7HotfixTests` (cancel из `.needsPassword`,
`.needsEncoding`, `.running` без double-removal, `.queued` без
регресса). Полный набор: 142/142 зелёные после фикса.

## 2026-06-23 — Этап 8 завершён (Preferences → реальная распаковка)

Связали настройки Этапа 7 с фактической распаковкой. То, что в Этапе 7
было «UI + персистентность», теперь применяется в `JobRunner`/
`Scheduler`/`AppCoordinator`.

**Что появилось:**

- `Engine/PostExtractActions.swift` — протокол с двумя методами
  (`openFolder`, `moveToTrash`) и `SystemPostExtractActions` через
  `NSWorkspace.open` / `NSWorkspace.recycle`. Инжектируется в
  `Scheduler`, тот пробрасывает в каждый создаваемый `JobRunner`.
- `Engine/DestinationPrompter.swift` — протокол с одним методом
  (`promptForDestination(archive:)`) и `SystemDestinationPrompter`
  через `NSOpenPanel`. Инжектируется в `AppCoordinator` (только для
  `.askEachTime`-сценария).
- `Domain/ExtractionOptions.swift` — два хелпера:
  - `wrapperFlag: Bool` — пробрасывает в `Archive.extract(wrapper:)`.
    `.onlyIfMultiple` → true, остальные → false.
  - `resolvedExtractURL(base:archive:) -> URL` — для `.always`
    возвращает `<base>/<стем-архива>/`, для остальных — `base`.
- `Domain/ArchiveJob.swift` — поле `destinationOverride: URL?`,
  set'ится при enqueue (`.askEachTime` пишет туда выбранную папку).
- `Domain/AppModel.swift` — `enqueue(urls:destinationOverride:)`
  принимает override; применяется ко всем создаваемым в этом батче
  `ArchiveJob`. Старый вызов `enqueue(urls:)` остаётся через дефолт
  `destinationOverride: nil`.
- `Engine/Scheduler.swift` — `resolvedDestination(for:)` (override
  > strategy), плюс пропуск через `PendingJob.init(job:destination:)`.
  В `launch` создаёт `JobRunner` с `actions` от планировщика.
- `Engine/JobRunner.swift` — использует `options.wrapperFlag` /
  `resolvedExtractURL`, до старта `extract` создаёт wrapper-папку
  через `FileManager.createDirectory(withIntermediateDirectories:)`.
  После успешного `.succeeded` вызывает `actions.openFolder` /
  `actions.moveToTrash` в зависимости от флагов.
- `NewTheUnarchiverApp.swift` — `AppCoordinator(defaults:destinationPrompter:)`
  принимает оба для DI. `openURLs(_:)` теперь:
  - Префильтрует папки (`isFileURL && !hasDirectoryPath`) до любого
    взаимодействия со стратегией.
  - Под `.nextToArchive` / `.fixed` — один батч-`enqueue` со всем
    массивом URL (избегаем O(N²) пересборки `active` Set).
  - Под `.askEachTime` — цикл по URL'ам, каждому свой `NSOpenPanel`
    через `destinationPrompter`. Пользовательский cancel пропускает
    архив (тихо).

**Зафиксированные дизайн-решения:**

- **Wrapper для `.always` — на Swift-стороне, не движке.** Engine не
  умеет «всегда оборачивать»; пишет в `<base>/<stem>/` с
  `wrapper: false`, мы создаём папку до старта. Plus rolling-back
  при ошибке не нужен — `createDirectory` идемпотентен, лишняя пустая
  директория — не катастрофа.
- **`?` default + body-resolve для сервисов** (`actions`/`prompter`/
  `defaults`) — `@MainActor`-инициализаторы нельзя вычислять как
  default value параметра. Парам делается опциональным, в теле init
  резолвится `actions ?? SystemPostExtractActions()`. Этот паттерн
  теперь применяется в `JobRunner.init`, `Scheduler.init`,
  `AppCoordinator.init`.
- **`destinationOverride: let` на ArchiveJob.** v1 не имеет UI чтобы
  изменить папку после enqueue — re-drop архива единственный способ.
  Если позже добавим UI «изменить папку», поле станет `var` с
  setter'ом.
- **NSOpenPanel блокирует main actor.** Это норма для
  user-initiated prompt; runModal — синхронный по дизайну, тестам
  его не нужно — они через `StubDestinationPrompter`.
- **moveToTrash идёт fire-and-forget.** `NSWorkspace.recycle`
  принимает completionHandler, мы передаём nil — ошибка (read-only
  volume / vanished archive) не блокирует пользователя.

**Тесты:** Этап 8 — 21 тест в сумме (`Stage8Tests` + `Stage8Extended`):
helpers, destination resolution, JobRunner с реальной FFI-распаковкой
для проверки post-actions, AppCoordinator `.askEachTime` со
stub-prompter (включая mixed-batch и filtered directories). Полный
набор приложения: **163/163 зелёные**.

**Тестовая изоляция от `.standard` UserDefaults:** ручная проверка
выявила, что тесты, использующие `AppCoordinator()` без аргументов,
читали из `.standard` (поделённый с реальным приложением). Если
пользователь успел поставить `.askEachTime` через Preferences UI,
тест дёргал реальный `NSOpenPanel`. Фикс — `AppCoordinator.init`
теперь принимает `defaults: UserDefaults` (default `.standard`),
все Stage 5/8-тесты переведены на `TestSupport.isolatedDefaults()`.

## 2026-06-23 — Stage 8: фаза ревью (шаги 7–10)

Три параллельных ревью-агента. Принято к исправлению:

- **`AppCoordinator.openURLs` делал O(N²) enqueue в цикле** — для
  `.nextToArchive` / `.fixed` каждый URL шёл отдельным `enqueue(urls:
  [url])`, а `enqueue` строит set из активной очереди заново на каждый
  вызов. Свёрнули в один batch-вызов per-strategy; `.askEachTime`
  остался циклом по дизайну (один promptPerArchive).
- **`PendingJob.init(_ job:)` convenience-init был мёртвым** — после
  Этапа 8 нигде не использовался (планировщик везде явно передаёт
  destination). Удалён.
- **`handleTerminal` мог планировать лишний sleep-Task** — для
  cancellation из `.running` сначала срабатывает `cancel(_:)`,
  затем scheduler-Task. Оба зовут `handleTerminal`. Добавлен ранний
  `guard queue.contains(...) else { return }` — если первый Task уже
  удалил строку, второй не плодит лишнюю работу.
- **`ExtractionOptions.wrapperFlag` switch с двумя `false`-ветками
  → одна проверка `wrapperMode == .onlyIfMultiple`.** Меньше шансов
  забыть ветку при добавлении нового кейса.
- **`appCoordinator_dirsAreFilteredBeforePrompt` фиксировал UX-баг
  как «acceptable»** — `.askEachTime` показывал NSOpenPanel для
  папки, которую `enqueue` всё равно выбросит. Префильтр в
  `openURLs` теперь отсекает директории до prompter'а. Тест
  обновлён: теперь проверяет `prompter.asked.isEmpty`.

**Отклонено:**

- **Вынести `archive.deletingPathExtension().lastPathComponent`
  в общий `archiveStem`** — преждевременно, один потребитель.
- **`Services`-struct для DI вместо параметра** — два сервиса
  (`actions`, `prompter`), агрегация перевешивает выгоду.
- **Убрать `Scheduler.actions` (Scheduler только пробрасывает)** —
  паттерн идентичен `model`/`probe` (Scheduler владеет всеми
  сервисами job-pipeline). Симметрия сильнее SRP-микрооптимизации.
- **`Stage8Tests` гоняют реальный FFI-extract ради post-actions
  проверок** — это behavioral test, не unit на implementation;
  ценность high, цена low (hello.7z — пара КБ).
- **`responses: [URL: URL?]` (Optional-of-Optional) → enum** —
  работает прозрачно через `?? nil`; tests не путаются.
- **`try?` на `createDirectory` молча глотает ошибку** —
  движок в `extract` всё равно вернёт `.io` с осмысленным
  сообщением; pre-flight — удобство, не контракт.
- **Stage7HotfixTests тестируют `app.handleTerminal(job)` напрямую**
  — это явный regression-guard на «double-fire безопасен», не
  тест реализации.
- **Ссылка из кода на `decisions.md`** — anti-pattern по практике
  проекта (комментарии описывают контракт, не журнал).

**Повторный прогон:** 163/163 в `NewTheUnarchiverTests` зелёные;
`BuildProject` — без ошибок.

## 2026-06-23 — Хотфикс Этапа 8: `.onlyIfMultiple` и single-file архивы

Ручная проверка показала: для архива из одного файла настройка
**«Только если внутри несколько объектов»** всё равно создавала папку
по имени архива. `.never` и `.always` работали.

**Причина — расхождение семантик.** Стадии 7–8 мапили
`.onlyIfMultiple` на `wrapper: true` в движке. Но:

- **Движок** (`wrapper: true`): «есть общий корень-папка → не оборачивать;
  иначе обернуть в `<стем>/`».
- **The Unarchiver** (`.onlyIfMultiple`): «один объект верхнего уровня
  (файл или папка) → не оборачивать; два и более → оборачивать».

Совпадают почти везде, **расходятся для архива с одним файлом в корне**:
у движка общего корня-папки нет → оборачивает; у оригинала один объект →
не оборачивает.

**Что починили:**

- `ExtractionOptions.wrapperFlag` удалён. Движку всегда передаётся
  `wrapper: false`.
- `ExtractionOptions.shouldWrap(topLevelCount:) -> Bool` —
  имплементирует оригинальную семантику: `.onlyIfMultiple` оборачивает
  при `topLevelCount > 1`, `.always` всегда, `.never` никогда.
- `ExtractionOptions.resolvedExtractURL(base:archive:topLevelCount:) -> URL`
  — единственный источник правды для целевой папки: если `shouldWrap`,
  возвращает `<base>/<стем-архива>/`, иначе `base`.
- `JobRunner.topLevelItemCount(in: [String]) -> Int` (`nonisolated static`)
  — считает уникальные первые компоненты путей. Распознаёт
  `foo/` + `foo/a.txt` как один корень. Сепаратор `/` — гарантия движка.
- `JobRunner.run()` теперь зовёт `archive.entries()` один раз, считает
  `topLevelCount`, передаёт его в `resolvedExtractURL`, всегда даёт
  движку `wrapper: false`.

**Rollback пустой обёртки на auth-failure:**
- Пре-создание директории (`FileManager.createDirectory`) нужно,
  потому что движок при `wrapper: false` не создаёт сам `destPath`.
- Но при `auth-failure` движок не пишет ничего (verify_password,
  Stage 6 hotfix), и мы рискуем оставить пустую `<dest>/<стем>/`.
- Через `var extractRan = false` + `defer { if !preExisted && !extractRan
  { removeItem(at: extractURL) } }`. Флаг ставится после возврата из
  `try await onQueue { ... extract ... }` (включая случай `aborted=true`
  — частично распакованную папку оставляем как было).
- **Почему success-флаг, а не `contentsOfDirectory.isEmpty`:**
  Finder/Spotlight может уронить `.DS_Store` в существующий dest до
  старта — пост-фактум-проверка пустоты ловит false-negative и оставляет
  обёртку зависшей.

**Контракт пересборки:**
- Хотфикс ломает один Stage 2-тест и два Stage 6-теста, которые
  кодировали **старое неправильное** поведение (single-file → wrapper).
  Они обновлены под правильный контракт. Это не регресс — тесты
  документировали баг.

**Тесты:** Stage8Hotfix — 10 (6 на `topLevelItemCount`, 3 на
`shouldWrap`, 1 интеграционный на `hello.7z` под `.onlyIfMultiple`,
проверяет flat-распаковку без обёртки). Полный набор: **174/174 зелёные**.

## 2026-06-23 — Stage 8 hotfix: фаза ревью (упрощённая, одним проходом)

Один simplify-агент — change небольшой, три параллельных были бы
overkill. Принято к исправлению:

- **Локальные алиасы `archiveURL`/`baseDestination`/`options`** в
  `JobRunner.run()` лишние — `job.url`/`destination`/`self.options`
  читаются нормально на месте. Дроп локалов.
- **`defer` на пустоту через `contentsOfDirectory.isEmpty` хрупкий** —
  если Finder уронил `.DS_Store` в существующий dest перед стартом,
  обёртка-сирота останется. Заменено на success-флаг `extractRan`.
- **Cross-reference в doc** `// see JobRunner.topLevelItemCount(in:)`
  убран — doc rot waiting to happen, инвариант сформулирован прямо.

**Отклонено:**

- **`topLevelItemCount(in: some Sequence<Entry>)`** — текущий вариант
  с `[String]` тестируется литералами без `import Newtua`. Generic
  усложнит сигнатуру ради сэкономленных миллисекунд.
- **`TestSupport.expectSucceeded(_ job:)` хелпер** — паттерн
  `if case .succeeded = job.state` встречается в 3–4 местах, но имя
  для хелпера громоздкое; экономия 2 строки на тест. Defer до 5+
  использований.

**Повторный прогон:** 174/174 в `NewTheUnarchiverTests` зелёные.

## 2026-06-23 — Хотфикс хотфикса: macOS-сайдкары в `topLevelItemCount`

Ручная проверка на свежесозданном `hello.txt.zip` (Finder-zip одного
файла) показала: `.onlyIfMultiple` всё равно делает обёртку. Внутри
`7zz l` показывает **два** entries: `hello.txt` и `__MACOSX/._hello.txt`
(AppleDouble-метаданные macOS).

Движок при распаковке **молча игнорирует** `__MACOSX/`, `.DS_Store`,
`._*` — это контракт ядра (CLAUDE.md в корне репо). На диск ложится
один файл. Но мой `topLevelItemCount` считал entries «как есть» —
видел два уникальных верхних компонента (`hello.txt` и `__MACOSX`) и
рапортовал «больше одного» → `.onlyIfMultiple` оборачивает в
`hello.txt/` (имя совпадает со стемом архива, выглядит как баг).

**Фикс:**

- `JobRunner.isMacOSSidecar(_:)` — приватный хелпер с тем же набором,
  что в движке (case-sensitive, по контракту движка).
- `topLevelItemCount(in:)` пропускает entries, у которых первый
  компонент пути — сайдкар. Для `hello.txt.zip` теперь возвращает 1,
  `.onlyIfMultiple` не оборачивает, файл лежит как `<dest>/hello.txt`.

**Тесты:** 7 новых в `Stage8HotfixTests`: `__MACOSX/`, `.DS_Store`,
`._foo` отдельно; сайдкар-only архив = 0; deep `foo/._bar` не
дублируется (его первый компонент `foo` уже учтён); реальная пара
`["hello.txt", "__MACOSX/._hello.txt"]` = 1 (якорь к багу из ручной
проверки). Полный набор: **180/180 зелёные**.

**Ревью (упрощённое, один simplify-агент):**
- Принято: docstring `isMacOSSidecar` явно отмечает case-sensitive
  по контракту движка (иначе будущий читатель «починит» как баг).
- Принято: удалён narrative-комментарий в
  `tlic_deepSidecarsDontDoubleCount` (имя теста уже самодокументирующее).
- Отклонено: предложение убрать `tlic_helloTxtZip_realPaths` как
  частично перекрывающий `tlic_macosx_skipped` — это якорь к
  реальному багу, ценность regression-guard сильнее.

## 2026-06-23 — Этап 9: смена скоупа на Quick Look-плагин для Finder

Исходный план этапа 9 («Space на строке очереди → превью первого
файла») переосмыслен. Решено:

- **Делаем Quick Look Preview Extension** (App Extension внутри
  основного `.app`), которое срабатывает в Finder по Space на
  поддерживаемом архиве. Внутри приложения превью не делаем —
  очередь в 99% случаев пробегает быстро, и UI там не востребован.
- **Контент превью — HTML-листинг дерева** содержимого архива:
  иконки, имя, тип, дата модификации, размер. Без распаковки.
- **API:** `QLPreviewProvider` + `QLPreviewingController.providePreview(for:)`,
  возврат `QLPreviewReply(dataOfContentType: .html, ...)`. Иконки
  файлов прикрепляются как `QLPreviewReplyAttachment` и ссылаются
  через `cid:`-схему.

**Зафиксированные правила рендера:**

- **Иконки** — системные через `NSWorkspace.shared.icon(for: UTType)`,
  кэшируются по UTI/расширению. Никаких эмодзи. Никаких SF Symbols.
- **Колонки** — имя + иконка, тип (file/dir/symlink), дата
  модификации (локализованная), размер (`ByteCountFormatter`).
- **Раскрытие папок** — корень всегда полностью раскрыт; внутренние
  узлы раскрыты, если у них ≤ 5 потомков, иначе свёрнуты. Реализация
  через `<details open>`/`<details>` без JavaScript.
- **Сайдкары macOS** (`__MACOSX/`, `.DS_Store`, `._*`) скрываются
  из дерева — иначе человек видит мусор, который движок всё равно не
  распаковывает.
- **Зашифрованный архив** (header-encrypted, listing без пароля
  невозможен) → показываем красивую статичную HTML-страницу
  «архив запаролен» с системной иконкой замка (NSWorkspace), без
  попытки запросить пароль (Quick Look по дизайну read-only).
- **Двойной клик в QL-окне** уже работает системно: открывает архив
  в нашем приложении и распаковка идёт по настройкам пользователя.
  Никакого UI с действиями в самом превью не добавляем.

**Архитектура (для тестируемости):**

- `ArchiveTreeBuilder` — pure `(entries) -> [TreeNode]`. Группирует
  плоский список путей в дерево, пропускает сайдкары, сортирует
  директории перед файлами, лексикографически.
- `ExpansionPolicy` — pure правило раскрытия (rootExpanded /
  thresholdChildren).
- `HTMLPreviewRenderer` — pure `(tree, locale) -> Data` (UTF-8 HTML).
  Экранирует HTML-спецсимволы в путях (XSS-защита).
- `IconCache` — `@MainActor` обёртка над `NSWorkspace.icon(for:)`,
  возвращает PNG-данные для прикрепления как `QLPreviewReplyAttachment`.
- `PreviewProvider` (в новом extension target) — тонкая обёртка:
  открывает `Archive`, строит дерево, рендерит HTML, собирает
  attachments, возвращает `QLPreviewReply`.

**TDD-минимум** (в основном тест-таргете, без extension):

- TreeBuilder: single file at root → один узел; shared root dir →
  вложенное дерево; неявная промежуточная папка («foo/sub/a.txt»
  без entry «foo/») → создаётся виртуальный folder; sidecars
  пропускаются; директории сортируются перед файлами; explicit
  `foo/` entry мерджится с содержимым.
- ExpansionPolicy: корень всегда раскрыт; узел с ≤5 детей раскрыт;
  с >5 — свёрнут.
- HTMLPreviewRenderer: эмитит валидный HTML с DOCTYPE; экранирует
  `<`, `>`, `&`, `"`; включает `ByteCountFormatter`-размер; включает
  локализованную дату; пустой архив → пустое состояние; encrypted
  fallback → статичная страница с локализованным текстом.

**Скоуп v1 — что НЕ делаем:**

- Поиск по дереву / `⌘F` (Quick Look по дизайну ограничен).
- Сортировка по другим колонкам.
- «Open this file inside the archive» (только через двойной клик
  всего архива из QL → наше приложение → распаковка).
- Selection / частичная распаковка через QL — Apple не даёт UI.

**Что делаем сразу, что — следом:**

- Сейчас: pure-Swift часть (TreeBuilder + ExpansionPolicy + Renderer)
  + полный тестовый набор в `NewTheUnarchiverTests`.
- Следом: новый extension target в Xcode (отдельный bundle с Info.plist
  и `NSExtension` dict), линковка `Newtua` + Rust-статика, тонкая
  обёртка `PreviewProvider`. Шаг 2 требует ручного добавления target в
  Xcode UI — это разовая конфигурация, инструкция готовится отдельно.

## 2026-06-23 — Этап 9: pure-Swift часть готова (TDD + simplify)

**Что сделано:**

- `QuickLook/PreviewInputEntry.swift` — engine-agnostic вход с конверсией
  `Int64 mtime → Date` на границе.
- `QuickLook/TreeNode.swift` — иммутабельный узел дерева
  (`file`/`directory`/`symlink`) с тремя static-конструкторами для
  выразительности тестов.
- `QuickLook/ArchiveTreeBuilder.swift` — pure `(entries) → [TreeNode]`,
  скрывает macOS-сайдкары, синтезирует промежуточные папки, сортирует
  через `localizedStandardCompare` (dirs-before-files).
- `QuickLook/ExpansionPolicy.swift` — порог раскрытия (`≤5` детей —
  открыто, корень всегда открыт).
- `QuickLook/HTMLPreviewRenderer.swift` — pure `(tree) → Data` (UTF-8
  HTML5), `<details>/<summary>` без JS, экранирование с fast-path.
- `Engine/MacOSSidecars.swift` — общий drop-list для `JobRunner` и
  `ArchiveTreeBuilder` (вынесен из дублирования по результатам ревью).

**Тесты:** `Stage9Tests.swift` (16 TDD-минимум) +
`Stage9ExtendedTests.swift` (20 расширенных). Полный прогон проекта —
**216/216 зелёные**, регрессий в этапах 1–8 нет.

**Ревью (`/simplify`, три параллельных агента):**

Принято и применено:
- **Дубль sidecar-логики** (HIGH, reuse + quality): `isMacOSSidecar` в
  `JobRunner` и `isSidecar` в `ArchiveTreeBuilder` — побайтно
  идентичные предикаты. Вынесено в `MacOSSidecars.matches` (две
  перегрузки: `String` и `Substring`), оба сайта вызывают общий
  helper. Контракт «дроп-лист движка» теперь живёт в одном файле.
- **`RenderContext` против парамлета** (HIGH, quality): три зависимости
  (`policy`, `sizeStyle`, `dateFormatter`) ходили через 4 уровня
  рекурсии. Завернул в `private struct RenderContext`, передаётся
  одним аргументом.
- **Пустые `<span></span>` через helper** (HIGH, quality): четыре
  ветви `if let mtime/size / else` сводились к одному
  `appendMetaSpan(class:text:)`. Добавлен короткий WHY-комментарий
  «пустые spans нужны grid-колонкам».
- **`inout String` + `reserveCapacity`** (HIGH, efficiency): рендер
  больше не возвращает `String` из каждого `renderNode`, а пишет в
  общий буфер. Резервируется capacity по числу узлов (~256 байт на
  узел). Для 10K-entry архивов это убирает ~20K промежуточных
  аллокаций.
- **Fast-path в `escape`** (MEDIUM, efficiency): сначала проверяем
  через `s.utf8`, есть ли вообще опасные байты (`&<>"'`). Если нет —
  пишем строку как есть. В типичных архивах большинство имён без
  спецсимволов, проход по `Character` не делается.
- **`let kind` в `MutableNode`** (MEDIUM, quality): `kind` был `var`
  ради `markDirectory`, но синтезированные узлы всегда `.directory`,
  и leaf'ы никогда не превращаются в parent'ов. Промоушн невозможен
  по построению — `var` снят, `markDirectory` упрощён до обновления
  `mtime`.
- **Сплющил `insert` через `makeChild`** (LOW, quality): switch по
  `entry.kind` теперь в одном месте; `insert` стал линейным проходом
  без вложенных условий.
- **Инкрементальный `pathSoFar`** (LOW, efficiency): убран
  `components[0...idx].joined()` на каждом уровне; путь строится
  одной строкой по мере спуска. Экономит N×depth строковых
  аллокаций.

Отклонено (с обоснованием):
- **Локализация HTML-строк** (MEDIUM, quality): захардкоженные
  «File / Folder / Symlink / Archive is empty / This archive is
  encrypted» — действительно нарушают сквозное правило RU+EN. Но
  Quick Look extension живёт в **отдельном bundle** со своим
  `Localizable.xcstrings`, и тащить ключи в основной бандл бессмысленно
  до того, как extension target создан. Откладываю на шаг
  «интеграция extension target»: создал target → добавил xcstrings →
  перевёл захардкоженные литералы на `String(localized:bundle:)`.
- **Фабрики `TreeNode.file/.directory/.symlink`** (MEDIUM, quality):
  предложено заменить на единый `init` с `Kind`. Отклонено — 36
  тестов активно используют фабрики, удобство выразительности
  превышает потенциальную «двусмысленность». В тестах конструктор
  `TreeNode.symlink(name: ..., size: 0, ...)` нормален — `size`
  имеет смысл и для симлинков (длина target-пути), пусть и редко.
- **`localizedStandardCompare` дорогой** (MEDIUM, efficiency):
  предложено заменить на простой `<` для глубоких подкаталогов.
  Отклонено — natural-order sort (`file2.txt` перед `file10.txt`)
  явно требуется тестом и проявится на любом архиве с нумерованными
  именами. Преждевременная оптимизация, ждём реальный сигнал лагания.
- **Ручной `escape` посимвольный цикл** (LOW, quality): остаётся как
  есть, корректно и предсказуемо; добавлен WHY-комментарий про
  порядок (амперсанд первым) на случай будущей «оптимизации» через
  `replacingOccurrences`.

**Открыто (handoff):**

Pure-Swift часть готова и закрыта тестами в основном таргете. Для
завершения этапа 9 нужны **ручные шаги через Xcode UI**, которых нельзя
автоматизировать через ассистента:

1. **File ▸ New ▸ Target ▸ Quick Look Preview Extension** (macOS).
   Имя — `NewTheUnarchiverQuickLook`, Bundle Identifier продолжает
   ID основного приложения с суффиксом `.QuickLook`.
2. Сгенерированный шаблон редактирует `PreviewProvider.swift` под
   `QLPreviewProvider` — заменить тело на тонкую обёртку: открыть
   `Archive`, конвертировать `Newtua.Entry → PreviewInputEntry`,
   вызвать `ArchiveTreeBuilder.buildTree` и `HTMLPreviewRenderer.render`,
   вернуть `QLPreviewReply(dataOfContentType: .html, contentSize: ...)`.
3. В Info.plist extension target — `NSExtension` → `QLSupportedContentTypes`
   = UTI всех поддерживаемых форматов (см. `SupportedFormats`).
4. Link `Newtua` package в extension target (тот же local-package
   reference, что и у основного).
5. Скопировать cargo Run Script phase в extension target — иначе
   `libnewtua_ffi.a` будет отсутствовать при первой сборке extension.
6. На сборке `xcodebuild` + ручной тест в Finder: drop фикстуру на
   рабочий стол → Space → должна появиться HTML-страница с деревом.
7. После работающего extension — локализация захардкоженных HTML-строк
   через `String(localized:bundle:)` с ключами в `Localizable.xcstrings`
   extension target'а, на EN и RU.

Шаги 1–7 — отдельная сессия (отдельный коммит). Pure-Swift код этого
коммита уже зелёный, готов к подключению.

## 2026-06-24 — Этап 9 polish: extension wired, иконки + summary + локализация

Пользователь добавил extension target в Xcode (Quick Look Preview
Extension с именем `NewTheUnarchiverQuickLook`). По ручной проверке в
Finder подтвердилось: HTML-превью открывается, дерево с папками
работает, иконки видны, summary в шапке («N files · M folders · X KB»)
читается. Запароленные `.zip` тоже листятся (central directory не
шифруется — оставлено как есть).

**В этом ходе сделано:**

- `IconCatalog.swift` — pure-маппинг `TreeNode → cid` для cid:-ссылок
  в HTML (`icon-folder`, `icon-symlink`, `icon-ext-<ext>`,
  `icon-file`). Содержит pure `utType(forCID:)` для extension'a.
  `cid(for:)` использует `URL(filePath:).pathExtension` (а не старую
  `NSString`-идиому, по результатам ревью).
- `ArchiveSummary.swift` — pure-агрегатор
  `(files, folders, totalBytes)`. Symlinks считаются файлами.
- `TreeNode.walk(_:)` — общий pre-order DFS. На него перешли
  `ArchiveSummary.summarize`, `IconCatalog.uniqueCIDs` и подсчёт узлов
  для `reserveCapacity` — раньше было три самописных обхода.
- `HTMLPreviewRenderer.swift` существенно расширен:
  - Иконка слева от имени через `<img src="cid:...">` — extension
    прикрепляет PNG к `QLPreviewReply.attachments[cid]`.
  - Колонка «Type» убрана (иконка её заменяет).
  - Собственный chevron вместо дефолтного `<details>`-маркера (QL
    его скрывает). Закодирован литералом `▸`/`▾`, не CSS-escape.
  - Шапка-summary «N files · M folders · X KB».
  - Свёрнутые папки показывают «N items» (плюрал-aware).
  - Локализация всех текстов через `NSLocalizedString` + xcstrings
    plural variations (one/few/many/other для русского).
  - Format строки для item-count-плюрала кэшируется в
    `RenderContext`, не резолвится по узлу.
  - CSS чистый: hover-фон, `--meta-font-size` переменная, чевроны
    через `::before { content: "▸" }`.
- `IconRenderer.swift` (extension-only) —
  `NSWorkspace.shared.icon(for: UTType)` → PNG. Cache локальный
  внутри `renderPNGs` (cross-call глобальный кэш убран — `provide
  Preview` запускается в свежем процессе, глобальное состояние
  бесполезно).
- `PreviewProvider.swift` — собирает cid'ы через
  `IconCatalog.uniqueCIDs`, рендерит PNG через `IconRenderer`, кладёт
  как `QLPreviewReplyAttachment` в reply.
- `Localizable.xcstrings` (main app) — 5 новых preview-ключей
  (`preview.state.empty`, `preview.state.encrypted`,
  `preview.summary.files/folders`, `preview.folder.itemCount`),
  EN+RU, plural variations для всех числительных.
- `NewTheUnarchiverQuickLook/Localizable.xcstrings` — отдельный
  каталог с теми же 5 ключами для extension bundle.
- **Тест-сторож** (`Stage9XcstringsSyncTests`) — читает оба
  xcstrings из репозитория, парсит JSON, требует чтобы наборы
  preview-ключей **байт-в-байт** совпадали. Это предотвращает
  будущий дрейф между двумя бандлами.

**Тесты:** 241/241 зелёные (старые 216 + Stage9PolishTests 25 новых +
3 теста-стража и summary-absence). Stage9PolishTests покрывает:
IconCatalog (cid, утечки cid, UT-резолвинг), ArchiveSummary
(счётчики), HTMLRenderer polish (иконки, summary, count, chevron-CSS,
без type-колонки).

**Ревью (`/simplify`, три агента):**

Принято и применено:
- Дубль обходов дерева → единый `TreeNode.walk(_:)`. На 50K узлов
  сэкономили ~3 рекурсии × N вызовов.
- `(NSString).pathExtension` → `URL(filePath:).pathExtension`
  (идиоматический Swift, согласован с соседним `FormatIcon.swift`).
- `IconRenderer` cache: убрали `nonisolated(unsafe)` + `DispatchQueue`
  + cross-call глобал. Локальный `var cache` внутри
  `renderPNGs` — `providePreview` запускается в свежем процессе.
- `summaryInHeader` тест: проверка через три `·`-разделителя в
  `<div class="summary">…</div>`, а не `html.contains("1")` (тот был
  бесполезен — любой непустой HTML содержит «1»).
- `RenderContext.locale` поле было неиспользуемое — убрал.
- CSS: чевроны через прямой `"▸"`/`"▾"` вместо CSS-escape
  `"\\25B8"` (хрупкий двойной escape); `--meta-font-size` для двух
  одинаковых значений.
- `htmlEscape(_:)`-врапер убран — `emptyState` и `encryptedFallback`
  переведены на `appendXxx(into:)` стиль, согласован с остальным
  рендером.
- `NSLocalizedString` для `preview.folder.itemCount` поднят из
  рекурсии в `RenderContext` (буферизирован в `itemCountFormat`).
- Дубль xcstrings: добавлен тест-сторож.

Отклонено (с обоснованием):
- IconRenderer ↔ FormatIcon объединение в общий слой —
  концептуально верно, но FormatIcon работает с `Image` (SwiftUI,
  @MainActor) и кэширует NSImage, IconRenderer работает с PNG-Data в
  extension target (тут нет @MainActor). Общий слой стоил бы
  больше, чем экономит. Отложено до момента, когда появится третий
  потребитель.
- `lockFocus` → `CGContext`/`CGImageDestination` — гипотетический
  выигрыш ~5–15 мс на превью на ~10 иконках. Без замеренной
  проблемы преждевременная оптимизация. Принято: оставить.
- `utType(forCID:)` парсит обратно cid → переход на
  `utType(for node:)`. Архитектурно cid — это **прозрачный токен
  для extension**, который PNG-рендерит без знания о node. Логично
  оставить как есть.
- `bundle: Bundle = .main` дефолт-параметр — корректное поведение
  (`.main` правильно резолвится в каждом из трёх контекстов: main
  app, extension, test).

**Открытое (handoff):**

- Локализация **только** в extension bundle и main app bundle.
  Test bundle берёт defaultValue (=английский) → тесты корректно
  locale-agnostic.
- На скриншоте в шапке видно «24 bytes» (английский) даже когда
  система на русском — это потому что `Locale.current` в Quick Look
  extension может оказаться не `ru_RU` (Apple ограничивает
  extension'ам locale). Если стоит цель показать русский размер
  байт — нужно отдельно подставить системную locale или передавать
  user-language из основного приложения через UserDefaults shared
  group. Откладываем до отдельного запроса от пользователя.
