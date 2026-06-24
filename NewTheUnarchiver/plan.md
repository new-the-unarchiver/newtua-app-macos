# План разработки macOS GUI для NewTheUnarchiver

## Контекст

Возвращаем сообществу легендарный The Unarchiver — модернизируем его GUI на
SwiftUI macOS 26+ поверх готового кроссплатформенного Rust-ядра
(`newtua-core`) через C-ABI (`newtua-ffi`) и Swift-обёртку (`Newtua`).

Цель v1: повторить весь пользовательский сценарий оригинала
(drop → очередь → прогресс → готово) и добавить две вещи, которых там не
было: **умную параллельную распаковку с учётом носителя и совместимости задач**
и **Quick Look-предпросмотр** содержимого архивов.

Все архитектурные решения уже зафиксированы в `decisions.md` — этот план
их не дублирует, а раскладывает в исполняемые этапы с TDD-циклом на каждом.

---

## Методология (TDD-цикл, применяется на КАЖДОМ этапе)

Жёсткое правило: **не переходить к следующему этапу плана, пока не выполнены
все шесть подшагов текущего**.

1. **Задача.** Однозначно сформулирована цель этапа и критерий завершения.
2. **TDD-тесты пишем первыми.** Минимальный набор тестов, описывающих
   ожидаемое поведение. Запускаем — должны быть **красными** (проверка,
   что они вообще что-то проверяют). До написания кода — учитываем все
   возможные проблемы из секции «Риски и краевые случаи» этапа.
3. **Минимальная реализация.** Ровно столько кода, сколько нужно, чтобы
   зелёные были все TDD-тесты. Без забегов вперёд.
4. **Прогон TDD-тестов до зелёного.** Не двигаемся дальше, пока все TDD-тесты
   зелёные.
5. **Расширенный тестовый набор** — unit / integration / end-to-end / edge:
   дописываем всё, что не вошло в TDD-минимум — ошибочные пути, краевые
   случаи, взаимодействия компонентов, UI через XCUIAutomation.
6. **Прогон полного набора до зелёного.** Правим код до полной зелени всех
   тестов.
7. **Краткий код-ревью**. Поиск дублей, мертвого кода, потенциальных
   уязвимостей, явных ошибок, переусложнений, неэффективностей.
   Составление списка найденных проблем.
8. **Анализ списка проблем**. Отсеиваем то, что является ложным
   срабатыванием, несущественным, обусловленным спецификой задачи или
   особенностями проекта.
9. **Исправление найденных проблем**. Исправляем то, что не отвергли.
10. **Прогон полного набора до зелёного**. Правим код до полной зелени всех
   тестов.
11. Только после этого — переход к следующему этапу.

**Инструменты тестирования:**
- Unit / integration: **Swift Testing** (`@Test`, `#expect`, `#require`).
- UI: **XCUIAutomation** в таргете `NewTheUnarchiverUITests`.
- Тесты Swift-обёртки: `swift test` в `bindings/swift/` (требует
  `cargo build -p newtua-ffi` перед запуском).
- Сборка Xcode-проекта: MCP-команда `BuildProject`.
- Быстрые диагностики компилятора: `XcodeRefreshCodeIssuesInFile`.

Эта методология также продублирована в `CLAUDE.md` как обязательная.

---

## Сквозные требования (применяются на всех этапах)

### Локализация интерфейса (RU + EN — обязательны к релизу)

К релизу v1 приложение поставляется **минимум в двух локалях: русской
и английской**. Локализация — не отдельный финальный этап, а сквозное
требование, применяемое с момента появления первой пользовательской
строки.

#### Что берём от движка, что локализуем сами

**От движка (`newtua-core` / `newtua-ffi`):**
- Только и исключительно — динамические сообщения об ошибках по коду
  статуса: `ntua_error_message(status, lang)`. EN/RU там уже есть.
  Передаём `Locale.current.identifier` (для не-EN/не-RU локалей в
  будущем — fallback на EN на стороне движка).

**Всё остальное локализуем сами в приложении:**
- Заголовки окон, меню, кнопки, тултипы, плейсхолдеры.
- Подписи в очереди («В очереди», «Извлекается %@», «Готово»,
  «Отменено» и т. п.).
- Inline-блоки пароля и кодировки («Введите пароль…», «Apply to All»,
  «Password Encoding:», «Filename Encoding:», «Result:», «Stop»,
  «Continue»).
- Все вкладки и поля Preferences.
- Тексты уведомлений и действия в них («Show in Finder»).
- Сообщения Quick Look-ошибок, не относящиеся к коду движка
  (например, «Файл больше 100 МБ — превью недоступно»).

#### Технические правила

- Все пользовательские строки — в **String Catalog**
  (`Localizable.xcstrings`). Никаких хардкод-строк в `Text(...)` /
  алертах / уведомлениях / заголовках окон / меню.
- В SwiftUI — `Text("key")` (автолокализация через каталог). В не-View
  контекстах — `String(localized: "key")`.
- Множественные числа — через variations в `Localizable.xcstrings`.
- Строки на обеих локалях (RU и EN) создаёт ассистент сам в момент
  добавления ключа. Человек переводы не пишет.

#### На каждом этапе плана

- Если этап вводит новые пользовательские строки — ключи и значения
  обеих локалей попадают в каталог одновременно с написанием
  TDD-тестов этапа.
- В TDD-минимум этапа, где это применимо, включаем проверку «строка
  идёт через каталог» (например, через XCUI-проверку, что текст в RU-
  и EN-сборке разный).
- В критерий завершения этапа — «новые строки переведены на RU и EN,
  TODO-маркеров в каталоге нет».

#### Перед финальной проверкой релиза v1

Отдельный шаг аудита: сборка приложения с
`-NSShowNonLocalizedStrings YES`, ручная проверка обеих локалей по
сценариям из этапов 4–9, поиск оставшихся хардкод-строк.

---

## Этап 0. Доработка Swift-обёртки `Newtua` и зачистка скаффолда

**Цель.** Прибрать шаблонный SwiftData-код приложения и сделать публичный
API пакета `Newtua` чисто-Swift (приложение не должно `import CNewtua`).

**Что сделать в обёртке** (`bindings/swift/Sources/Newtua/Newtua.swift`):
- `public enum ErrorCode` со всеми кейсами `NtuaStatus`. `NewtuaError.code`
  переключить на этот enum.
- `public struct Progress` со всеми полями `NtuaProgress` в Swift-формате
  (`Int`, `String?`, `UInt64`, `Bool`).
- `public final class CancellationToken` на базе
  `OSAllocatedUnfairLock<Bool>` (см. § 5.3 в decisions.md).
- `Archive.extract(...) async throws -> ExtractReport` — асинхронная
  обёртка, внутри запускает синхронный `extract` на личной
  `DispatchQueue` задачи. Принимает опциональный `CancellationToken`
  и колбэк `(Progress) -> Void`, который сама обёртка хопит на
  `@MainActor`.
- `Archive.read(_:) async throws -> Data` — аналогично.
- Колбэки больше не отдают `NtuaProgress`, отдают `Progress`.

**Что сделать в приложении:**
- Удалить `NewTheUnarchiver/Item.swift`.
- В `NewTheUnarchiverApp.swift` убрать `import SwiftData`,
  `import CNewtua`, `Schema([Item.self])`, `ModelContainer`,
  `.modelContainer(...)`. Оставить только `WindowGroup { ContentView() }`.
- В `ContentView.swift` убрать `@Query`, `NavigationSplitView`,
  `addItem`/`deleteItems`. Заменить на временный плейсхолдер.

**Риски и краевые случаи (закладываем в тесты сразу):**
- Колбэк прогресса вызывается из C-потока, не из главного. Кейс
  thread-safety: обёртка не должна падать, если closure захватывает
  `@MainActor`-объекты.
- Кооперативная отмена через `CancellationToken.cancel()` после старта —
  должна реально прерывать.
- Передача `nil` пароля/кодировки — штатный путь.
- Неверный пароль на запароленный архив → `ErrorCode.wrongPassword`.
- Открытие архива, которого нет на диске → `ErrorCode.io`.
- Многократный `entries()` подряд на одном `Archive` — не утечка.
- Очень длинный путь в имени файла — не обрезается, валидный UTF-8.

**TDD-минимум:**
- `errorCode_mapsAllNtuaStatusValues()` — для каждого значения
  `NtuaStatus` есть соответствующий `ErrorCode`.
- `extract_async_succeedsOnFixture()` — открыть `hello.7z` из фикстур
  ядра, распаковать в `tmp`, проверить `extracted == 1`, `failed == 0`,
  `aborted == false`.
- `extract_async_cancellationStopsMidWay()` — отменить через
  `CancellationToken` после первого `progress.started`, проверить
  `aborted == true`.
- `progressCallback_isOnMainActor()` — через
  `MainActor.assertIsolated()` внутри колбэка.

**Расширенный набор:**
- Unit: `ErrorCode` ↔ `NtuaStatus` симметрия; поля `Progress`; `read()`
  на всех видах entries; `read` на encrypted без пароля → ошибка.
- Integration: `tar.gz` → list → extract → проверить файлы на диске.
- E2E: цикл «open → entries → read первого → extract всех → проверка
  содержимого диска».
- Edge: невалидный путь; пустой архив; кодировка `cp866`/`shift_jis` на
  фикстуре с не-ASCII именами.

**Критерий завершения этапа 0.**
- `swift test` в `bindings/swift/` полностью зелёный.
- `BuildProject` для Xcode-проекта собирается без ошибок.
- В приложении нет `import SwiftData` и `import CNewtua`.

---

## Этап 1. Доменная модель: `AppModel`, `ArchiveJob`, состояния

**Цель.** Pure-Swift модель очереди задач без UI и без движка — машина
состояний, на которой потом строится всё остальное.

**Файлы (новые):**
- `NewTheUnarchiver/Domain/JobState.swift` — enum состояний.
- `NewTheUnarchiver/Domain/ArchiveJob.swift` — `@Observable` задача.
- `NewTheUnarchiver/Domain/AppModel.swift` — `@Observable` корень.
- `NewTheUnarchiver/Domain/ExtractionOptions.swift` — `wrapperMode`
  (`.never/.onlyIfMultiple/.always`), `destinationStrategy`,
  `openFolderAfter`, `moveToTrashAfter`.

**Ключевое:**
- Только `Observation` (`@Observable`), Combine не используем.
- `enum JobState`: `queued`, `running(Progress)`, `needsPassword(reason)`,
  `needsEncoding(EncodingPrompt)`, `succeeded(ExtractReport)`,
  `failed(ErrorCode)`, `cancelled`.
- `AppModel.queue: [ArchiveJob]` — FIFO.
- `AppModel.sharedPassword: String?` — только в памяти, для Apply-to-All.
- `AppModel.enqueue(urls: [URL])` — дедупликация по
  `URL.standardizedFileURL` (если архив уже в очереди в `queued`/`running`
  — не добавляем).

**Риски и краевые случаи:**
- Дубль URL в `enqueue` — не плодим.
- Отмена активной задачи через × переключает её в `.cancelled`, но строка
  не исчезает мгновенно (исчезает после завершения, как в оригинале).
- `sharedPassword` устанавливается только когда галочка «Apply to All»
  отмечена.

**TDD-минимум:**
- `enqueue_addsJob_andDeduplicates()`.
- `jobState_transitionsAreValid()` — из `.succeeded` нельзя в `.queued`.
- `cancelRunning_marksAsCancelled_keepsRowUntilFinish()`.
- `sharedPassword_isOnlySetWhenApplyToAllChecked()`.

**Расширенный набор:**
- Unit: все переходы состояний; equatable для `JobState`.
- Edge: пустая очередь; очередь из 50 задач; ресет очереди.

**Критерий завершения.** Тесты зелёные в `NewTheUnarchiverTests`.

---

## Этап 2. Движок очереди: последовательная распаковка с прогрессом

**Цель.** Один `ArchiveJob` за раз: open → entries → extract → progress
→ done/failed/cancelled. **Без** умного планировщика — он отдельный этап.

**Файлы (новые):**
- `NewTheUnarchiver/Engine/JobRunner.swift` — обёртка вокруг `Archive`,
  владеет `DispatchQueue(label: "newtua.job.<uuid>")` (§ 5.2 brief).
- `NewTheUnarchiver/Engine/ProgressThrottle.swift` — буферизация
  обновлений, не чаще ~24 Гц (§ 5.5 decisions).
- `NewTheUnarchiver/Engine/QueueDriver.swift` — последовательный цикл
  «возьми следующий queued → запусти JobRunner → жди → следующий».

**Риски и краевые случаи:**
- Прогресс приходит из C-потока — все обновления `ArchiveJob.state`
  идут через `MainActor.run`.
- Отмена в момент `started` (между entries) и в момент `bytes_written`
  (внутри entry) — оба пути корректно завершаются с `aborted == true`.
- На `Encrypted` runner останавливается и отдаёт состояние
  `needsPassword`, не пытается заново автоматически.
- Архив с тысячами entries — троттлинг прогресса не отстаёт от UI.

**TDD-минимум:**
- `runner_completes_simpleArchive()` — на `hello.7z`.
- `runner_reportsNeedsPassword_onEncrypted()` — на фикстуре encrypted
  zip из `crates/newtua-core/tests/fixtures/`.
- `runner_cancellation_setsCancelled()`.
- `throttle_emitsAtMost24Hz_underBurst()` — 1000 прогрессов за секунду
  → ≤ 25 эмитов в UI.

**Расширенный набор:**
- Integration: две задачи в очереди — первая закончилась, вторая
  стартовала.
- E2E: распаковать `hello.tar.gz` из фикстур → проверить файлы в `tmp`.
- Edge: пустой архив; архив только из каталогов; архив с одним
  крупным entry; архив с CJK именами.

**Критерий завершения.** Все тесты зелёные.

---

## Этап 3. Умный планировщик параллели

**Цель.** Заменить последовательный `QueueDriver` из этапа 2 на
планировщик с предикатом совместимости задач (см. decisions.md →
2026-06-22 «Параллельная распаковка»).

**Файлы (новые):**
- `NewTheUnarchiver/Engine/VolumeProbe.swift` — протокол
  `VolumeProbing` с `isInternal(URL) -> Bool` и
  `mediumType(URL) -> .ssd | .hdd | .unknown`. Реализация
  `SystemVolumeProbe` через `URLResourceValues` + IOKit + Disk
  Arbitration. Внутренний кеш по mount-path.
- `NewTheUnarchiver/Engine/CompatibilityPredicate.swift` — чистая
  функция `(JobA, JobB, VolumeProbing) -> Bool`.
- `NewTheUnarchiver/Engine/Scheduler.swift` — заменяет `QueueDriver`.

**Риски и краевые случаи:**
- IOKit может вернуть `.unknown` (сетевая шара, экзотический USB) —
  предикат трактует `unknown` как несовместимо (фолбэк на serial).
- Папка назначения двух задач совпадает → блокируем именно эту пару,
  другие пары идут.
- Запароленный архив занимает «слот» пользовательского ввода — другие
  запароленные ждут, не запароленные идут параллельно.
- `activeProcessorCount` меняется в Low Power Mode — потолок
  динамический: `min(ProcessInfo.processInfo.activeProcessorCount, 4)`.
- Кеш volume probe в v1 — простой in-memory без инвалидации на unmount.

**TDD-минимум (на моках `VolumeProbing`):**
- `predicate_blocksParallel_ifEitherIsExternalOrHDD()`.
- `predicate_blocksParallel_ifSameDestination()`.
- `predicate_blocksParallel_ifEitherEncrypted()`.
- `predicate_allowsParallel_ifInternalSSD_differentDest_noPassword()`.
- `scheduler_caps_at_min_cpuCount_and_4()`.
- `scheduler_picksFirstCompatible_fromQueue()`.

**Расширенный набор:**
- Integration: реальный `SystemVolumeProbe` на корне `/` — должен
  определить SSD/internal.
- E2E: три фикстуры одновременно — параллель действительно ускоряет
  относительно суммы индивидуальных.
- Edge: один CPU (через искусственный мок) → fallback на serial; mid-run
  изменение `activeProcessorCount`.

**Критерий завершения.** Тесты зелёные; ручной замер «параллель быстрее»
записан в `decisions.md`.

---

## Этап 4. Главное окно — список очереди

**Цель.** Окно очереди с двумя вариациями строки (queued / running),
кнопка ×, материал Liquid Glass, авто-скрытие при пустой очереди.

**Файлы (новые):**
- `NewTheUnarchiver/Views/QueueWindow.swift`.
- `NewTheUnarchiver/Views/JobRowView.swift` (две вариации в одном файле).
- `NewTheUnarchiver/Views/FormatIcon.swift` — иконка формата по
  расширению через `NSWorkspace.shared.icon(for: UTType)`.

**API для проверки через DocumentationSearch перед кодом:**
- `Material.glass` / `.glassEffect` для Liquid Glass на macOS 26.
- Поведение `WindowGroup` «скрывать когда пусто» / альтернатива через
  `NSApplicationDelegate`.
- `dropDestination(for: URL.self)` — тип ввода на macOS.

**Риски и краевые случаи:**
- Окно мигает при быстром появлении/исчезновении задач — задержка
  ~300 мс перед сокрытием.
- Прогресс-бар дёргается назад — игнорировать обновления с
  `bytes_written` меньше предыдущего.
- Длинное имя файла — truncate middle, полное в tooltip.

**TDD-минимум (XCUIAutomation):**
- `ui_emptyState_windowHidden()`.
- `ui_dropFile_addsRow()`.
- `ui_running_showsProgressBar()`.
- `ui_cancelButton_removesRow_afterCompletion()`.

**Расширенный набор:**
- UI: 5+ задач в столбце; ресайз окна; светлая/тёмная темы.
- Visual: сверка по `docs/gui_references/`.

**Критерий завершения.** UI-тесты зелёные, визуально близко к референсу.

---

## Этап 5. Сценарии открытия (drop, double-click, File ▸ Open…)

**Цель.** Все три способа открыть архив работают и приводят к
одному и тому же `AppModel.enqueue`.

**Что сделать:**
- `Info.plist` → `CFBundleDocumentTypes` + Imported/Exported Type
  Identifiers с UTI для всех текущих форматов движка (см.
  `docs/Supported formats.md` — на v1 закрываем «Popular»-секцию).
- В `NewTheUnarchiverApp` подписаться на `onOpenURLs` (SwiftUI) и/или
  `NSApplicationDelegate.application(_:openFiles:)`.
- `File ▸ Open…` через `fileImporter` с фильтром по UTI.
- Drop на корневой view — уже из этапа 4.

**Риски и краевые случаи:**
- Перетаскивание папки, а не архива — игнорируем (UI-сообщение
  «не архив»).
- Один и тот же файл открыт двумя способами одновременно — дедупликация
  в `enqueue` (этап 1) спасает.
- Двойной клик по архиву, не отнесённому к нам — система выбирает
  другой опeнер, нас не касается.

**TDD-минимум:**
- `enqueue_ignoresDirectories()`.
- `enqueue_dedupesAcrossSources()`.

**Расширенный набор:**
- UI: `app.launchArguments = ["--open", archive.zip]` → задача появилась.
- E2E: drag через AppleScript-кликер (если стабильно).

**Критерий завершения.** Все три сценария проверены, фактически
зарегистрированные UTI зафиксированы в `decisions.md`.

---

## Этап 6. Встроенный запрос пароля и кодировки

**Цель.** В точности повторить inline-блоки из оригинала
(`docs/gui_references/05_the-unarchiver.webp`,
`The-Unarchiver-1.jpg`): поле пароля + чекбокс «Apply to All» +
Stop/Continue; селектор кодировки с живым `Result:`-превью.

**Что сделать:**
- В `JobRowView` добавить варианты `needsPassword` / `needsEncoding`,
  раскрывающие строку в inline-форму.
- Обработчик пароля: при Continue → создать новый `Archive` с этим
  паролем; при ошибке → вернуть в `needsPassword`. Apply to All →
  `AppModel.sharedPassword`.
- Обработчик кодировки: на каждое изменение значения **с дебаунсом
  ~200 мс** реоткрывает `Archive` и обновляет `Result:` (берёт первый
  non-trivial path из `entries()`).
- В `Scheduler` при `needsPassword` первая попытка — молча с
  `AppModel.sharedPassword` (если есть); только если не подошёл,
  показываем prompt.

**Риски и краевые случаи:**
- Дебаунс для кодировки — слишком частые реопены недопустимы.
- `sharedPassword` — только в памяти, никаких записей на диск или в лог.
- Пустой пароль / Unicode / пробелы в начале-конце.
- Смена кодировки на ту же, что стоит — no-op (не реоткрываем).

**TDD-минимум:**
- `applyToAll_setsSharedPassword_andRetriesNextEncrypted()`.
- `wrongPassword_returnsToNeedsPassword_state()`.
- `encodingChange_reopensArchive_andUpdatesPreview()` (CJK фикстура).
- `encodingChange_isDebounced_200ms()`.

**Расширенный набор:**
- Edge: пустой пароль; Unicode-пароль; пароль с пробелами.
- Edge: смена кодировки на текущую → нет реопена.

**Критерий завершения.** Inline-форма ведёт себя как референс.

---

## Этап 7. Окно настроек (Preferences)

**Цель.** Три вкладки в стиле оригинала: Archive Formats / Extraction /
Advanced.

**Файлы (новые):**
- `NewTheUnarchiver/Settings/SettingsScene.swift` —
  `Settings { TabView { ... } }`.
- `NewTheUnarchiver/Settings/ArchiveFormatsTab.swift` — `Table` со
  списком форматов и чекбоксами + Select All / Deselect All.
- `NewTheUnarchiver/Settings/ExtractionTab.swift` — destination,
  wrapper-режим (Never / Only if more / Always), modification date,
  postActions (open folder, move to trash).
- `NewTheUnarchiver/Settings/AdvancedTab.swift` — только селектор
  «Filename encoding: Detect automatically / список». Threshold убран.

**Хранение:** `@AppStorage`/`UserDefaults` + `@Observable`-фасад.

**Риски и краевые случаи:**
- Динамическое включение/отключение UTI через
  `LSSetDefaultRoleHandlerForContentType` требует подписи и может
  не работать в Sandbox. Если упрёмся — оставляем фиксированный набор в
  Info.plist, UI чекбоксов превращаем в «не наш формат → серый»
  (визуальный, без эффекта на ассоциации). Решение по факту проверки.

**TDD-минимум:**
- `settings_persistence_writesAndReadsBack()`.
- `extractionOptions_defaults_matchOriginalUnarchiver()` — Only if
  more than one top-level item / current date / no open folder /
  no trash.

**Расширенный набор:**
- UI: переключение вкладок; чекбоксы массово через Select All;
  персистентность между запусками.

**Критерий завершения.** Окно открывается по ⌘,. Три вкладки.
Значения сохраняются.

---

## Этап 8. Пост-действия и применение опций распаковки

**Цель.** Связать настройки этапа 7 с фактической распаковкой:
wrapper-режим, destination, openFolder, moveToTrash, уведомления.

**Что сделать:**
- `JobRunner` принимает `ExtractionOptions` из `AppModel`.
- Wrapper-режим:
  - `.never` → `wrapper: false`.
  - `.onlyIfMultiple` → `wrapper: true` (нативное поведение).
  - `.always` → перед `extract` вызвать `entries()`, посчитать
    common-root; если есть — после успешной распаковки физически
    обернуть содержимое в папку с именем архива. Rollback при ошибке
    (best-effort: вернуть исходное расположение).
- `NSWorkspace.activateFileViewerSelecting(_)` для «Open extracted folder».
- `NSWorkspace.recycle(_:completionHandler:)` для «Move archive to trash».
- `UNUserNotificationCenter` — нотификация «Готово» с action
  «Show in Finder».

**Риски и краевые случаи:**
- `Always` без расширения C-ABI — физическое перемещение хрупко.
  План B: расширить ABI на `wrapper_mode` enum. Решение по итогам
  пробной Swift-реализации.
- Уведомления требуют пользовательское разрешение при первом показе.
- Move to trash может упасть на read-only volume — поймать, показать в
  UI понятную ошибку.

**TDD-минимум:**
- `wrapperAlways_addsWrapper_evenIfCommonRootExists()`.
- `wrapperAlways_rollbackOnFailure()`.
- `postActions_openFolder_calledOnSuccess()` (мок workspace).
- `postActions_moveToTrash_calledOnSuccess()` (мок).
- `notification_authorization_requestedOnce()`.

**Расширенный набор:**
- E2E: реальная распаковка с «open folder» включенным → Finder
  становится frontmost.

**Критерий завершения.** Все опции из Preferences реально применяются.

---

## Этап 9. Quick Look-предпросмотр содержимого архива

**Цель.** При выделении задачи в очереди по Space показывается
Quick Look-превью первого entry архива.

**Уточнение скоупа.** В оригинале нет браузера entries — Quick Look
у нас на v1 показывает превью **первого file-entry архива**. Расширение
до выбора конкретной entry откладываем на v2.

**Файлы (новые):**
- `NewTheUnarchiver/QuickLook/QuickLookCoordinator.swift` —
  делегат `QLPreviewPanel`.
- `NewTheUnarchiver/QuickLook/TempFileVendor.swift` — выдача и
  очистка `tmp`-файлов под Quick Look.

**API для проверки через DocumentationSearch:**
- Современный путь к Quick Look в SwiftUI macOS 26 — `quickLookPreview(_:)`
  модификатор vs прямой `QLPreviewPanel`.

**Риски и краевые случаи:**
- `read` читает entry в память целиком — лимит «не превью > 100 МБ»
  с понятным сообщением в UI.
- Quick Look хочет URL — пишем во временный файл, удаляем по dismissal.
- `Archive` не thread-safe — `read` идёт на job-queue, презентация
  на main.
- Encrypted архив без пароля → ошибка с подсказкой «нужен пароль».

**TDD-минимум:**
- `quickLook_writesTmpFile_andReturnsItsURL()`.
- `quickLook_skipsLargeEntries_above100MB()`.
- `tempFileVendor_cleansUpOnDismiss()`.

**Расширенный набор:**
- UI: открыть фикстуру → нажать Space → панель появилась.
- Edge: encrypted архив без пароля → понятное сообщение.

**Критерий завершения.** Quick Look работает на zip/7z/tar с текстом /
png / pdf внутри.

---

## Этап 10. XCFramework и Release-распространение

**Цель.** Перевести линковку движка с «cargo + статическая `.a`» на
готовый артефакт `Newtua.xcframework` с динамической библиотекой
внутри. Без этого Release-сборка некорректна (Package.swift жёстко
указывает на `target/debug`), а Quick Look-extension получает свою
дубликатную копию Rust-кода в `.appex` (в Debug это ~22 МБ
дополнительно к ~23 МБ в app).

**Принятые решения** (см. `decisions.md` за 2026-06-24):
- Динамическая библиотека (`libnewtua_ffi.dylib`) вместо статической:
  release-вариант весит ~2,1 МБ против 27 МБ у `.a`. После Embed в
  `.app/Contents/Frameworks/` — одна копия на bundle.
- Архитектура — только `aarch64-apple-darwin`. Universal не нужен.
- `MACOSX_DEPLOYMENT_TARGET=26.0` задаётся env-переменной в скрипте
  сборки, не в `Cargo.toml`.
- `install_name` dylib — `@rpath/Newtua.framework/Versions/A/Newtua`,
  задаётся через `install_name_tool -id` после сборки framework (не в
  ядре Rust — граница ответственности).
- XCFramework в git не коммитим — генерируется build-скриптом, попадает
  в `.gitignore`.
- В ядре Rust (`crates/`, `Cargo.toml`) **ничего не меняется**:
  `crate-type = ["staticlib", "cdylib", "rlib"]` уже стоит с первого
  FFI-коммита. См. `docs/handoff-2026-06-24-newtua-ffi-cdylib.md` и
  `docs/reply-2026-06-24-newtua-ffi-cdylib.md`.

**Файлы (новые):**
- `apps/macos/tools/build-newtua-xcframework.sh` — собирает release
  dylib, упаковывает в `Newtua.framework`, оборачивает в XCFramework.
- `.gitignore` — добавить `bindings/swift/Newtua.xcframework/`.

**Файлы (правятся):**
- `bindings/swift/Package.swift` — `unsafeFlags` заменяются на
  `.binaryTarget(name: "CNewtua", path: "Newtua.xcframework")` плюс
  системные библиотеки переезжают в `linkerSettings` на Swift-таргете.
- Xcode-проект:
  - Build Phase Cargo-скрипт упрощается: вызывает
    `build-newtua-xcframework.sh` (но **не** делает свой cargo build),
    и только если XCFramework отсутствует.
  - Основной таргет `NewTheUnarchiver` — Newtua framework в **Embed &
    Sign**.
  - Таргет `NewTheUnarchiverQuickLook` — Newtua framework в **Do Not
    Embed** (использует embedded в родительский bundle через `@rpath`).
- `bindings/swift/README.md` — отметка «перед `swift test` собрать
  XCFramework скриптом».

**Риски и краевые случаи:**
- `@rpath` resolution для `.appex`: extension живёт в
  `.app/Contents/PlugIns/X.appex/Contents/MacOS/`, framework — в
  `.app/Contents/Frameworks/`. Поэтому LC_RPATH у extension должен быть
  `@executable_path/../../../../Frameworks`. Xcode выставляет его сам
  при правильной настройке embed flags — но проверить нужно по
  `otool -l` бинаря extension.
- Подпись framework и hardened runtime — Xcode сделает автоматически
  при Embed & Sign, но проверить, что Code Sign Identity у framework
  совпадает с identity .app/.appex.
- `swift test` в `bindings/swift/` после перехода на binaryTarget
  больше не вызывает cargo сам — требуется заранее собранный
  XCFramework. Если XCFramework нет — `swift test` падает с понятной
  ошибкой про missing binary. Документируется в `bindings/swift/README.md`.
- Кэш XCFramework и пересборка: если ABI ядра изменилось, build-скрипт
  должен принудительно пересобирать XCFramework. Простой способ —
  удалять старый каталог в начале скрипта.

**TDD-минимум** (smoke-проверки инфраструктуры):
- `script_produces_xcframework_with_dylib_inside()` — после запуска
  скрипта в `bindings/swift/Newtua.xcframework/` лежит framework с
  бинарём.
- `dylib_has_correct_install_name()` — `otool -D` на собранной dylib
  показывает `@rpath/Newtua.framework/Versions/A/Newtua`.
- `appex_does_not_contain_own_rust_code()` — после сборки .app в
  `Build/Products/Debug/` бинарь `.appex` не содержит rust-символов
  (через `nm`/`otool -L` проверяем, что Newtua подключается как
  `@rpath`-зависимость, а не статически).

**Расширенный набор:**
- BuildProject Debug — зелёный, без warnings.
- BuildProject Release — зелёный, без warnings.
- `swift test` в `bindings/swift/` — все 20/20 зелёных против новой
  XCFramework-сборки.
- Полный прогон `NewTheUnarchiverTests` (241+) с тайм-аутами — зелёный.
- Полный прогон `NewTheUnarchiverUITests` — зелёный.
- Запустить .app из `Products/`, открыть архив через Quick Look (Space
  в Finder) — extension работает (превью отображается).

**Критерий завершения.** XCFramework собирается одной командой, оба
таргета линкуются с одной копией Newtua внутри bundle, все тесты
зелёные, размер .app меньше текущего за счёт устранения дубля Rust-кода
в `.appex`.

---

## Финальная проверка релиза v1

После завершения всех 10 этапов:

1. `cargo build -p newtua-ffi --release --target aarch64-apple-darwin`
   чисто собирается (выполняется build-скриптом этапа 10).
2. `cd bindings/swift && swift test` — все 20/20 зелёные против
   XCFramework.
3. `BuildProject` в Xcode — без warnings, **Debug + Release**.
4. `XcodeListNavigatorIssues` — пусто.
5. Все тесты в `NewTheUnarchiverTests` и `NewTheUnarchiverUITests` —
   зелёные.
6. Записать «v1 готов, дата» в `decisions.md`.

---

## Критические файлы, на которые опираемся

- `bindings/swift/Sources/Newtua/Newtua.swift` — текущая Swift-обёртка
  (правится на этапе 0).
- `bindings/swift/Sources/CNewtua/newtua.h` — C-ABI, ссылка для проверки
  ошибок и типов.
- `apps/macos/NewTheUnarchiver/NewTheUnarchiver/NewTheUnarchiverApp.swift`
  — точка входа SwiftUI (зачищается на этапе 0).
- `apps/macos/NewTheUnarchiver/NewTheUnarchiver/ContentView.swift` —
  заменяется на `QueueWindow` к этапу 4.
- `apps/macos/NewTheUnarchiver/NewTheUnarchiver/Item.swift` — удаляется
  на этапе 0.
- `apps/macos/NewTheUnarchiver/CLAUDE.md` — пополняется секцией
  «Методология» сразу после утверждения плана.
- `apps/macos/NewTheUnarchiver/decisions.md` — журнал, который
  обновляем по ходу работы.
- `apps/macos/CLAUDE.md` — технический бриф (не меняем).
- `crates/newtua-core/tests/fixtures/` — фикстурные архивы для тестов
  всех этапов.
