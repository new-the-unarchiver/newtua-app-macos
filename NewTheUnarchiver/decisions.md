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
