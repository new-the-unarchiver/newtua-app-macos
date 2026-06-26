# Архитектура macOS GUI — карта кода

Этот документ — **карта текущего устройства кода** приложения: какие слои
есть, что делает каждый файл и как они связаны. Он отвечает на вопрос
«как устроено сейчас», в отличие от `decisions.md` (журнал «почему»)
и `plan.md` (исторический «что делали по этапам»).

Источник истины — сам код. Если документ разойдётся с кодом, прав код;
такую правку нужно отразить здесь и зафиксировать в `decisions.md`.

Статус: **v1 готов** (2026-06-24). Подробности — в `CLAUDE.md` и
`decisions.md`.

---

## 1. Границы и принцип разделения

Приложение **только распаковывает и показывает** архивы, никогда не
создаёт. Жёсткое правило: вся логика архивов (определение формата,
распаковка, пароли, кодировки, защита путей, права/время/симлинки) живёт
в Rust-движке. Swift — это **чистый интерфейс плюс оркестрация**. Если в
Swift приходится разбирать байты архива, считать пути извлечения или
санировать имена — это сигнал, что фича должна уйти в C-ABI или
Swift-обёртку, а не в приложение.

Полный технический контракт с движком — в `apps/macos/CLAUDE.md`.

## 2. Цепочка линковки Rust → Swift

```
crates/newtua-core  →  crates/newtua-ffi (C-ABI, newtua.h)
                    →  bindings/swift  (Swift-пакет Newtua)
                    →  приложение (import Newtua)
```

- `newtua-ffi` отдаёт библиотеку и заголовок `include/newtua.h`.
- `bindings/swift/Sources/Newtua/Newtua.swift` — идиоматичная обёртка.
  Приложение импортирует **только** `Newtua`, никогда не `CNewtua`.
- С Этапа 10 движок линкуется через готовый `Newtua.xcframework`
  (в git не коммитится, собирается `tools/build-newtua-xcframework.sh`,
  только `aarch64-apple-darwin`, dylib через `@rpath`). Детали — в
  `CLAUDE.md`, раздел «Линковка движка через XCFramework».

### Ключевое из Swift-обёртки (`Newtua`)

- `Archive` — **не потокобезопасен**: держит непрозрачный указатель на
  однопоточный Rust-ридер. Контракт: не вызывать методы одного `Archive`
  из двух потоков одновременно. `async`-методы сериализуются внутри на
  приватной `DispatchQueue`.
- Публичные типы — чисто-Swift: `ErrorCode`, `NewtuaError`, `Entry`,
  `EntryKind`, `Progress`, `ExtractReport`, `CancellationToken`.
- `extract`/`read` есть в синхронном и `async`-вариантах. У `async`
  прогресс-колбэк автоматически прыгает на главный поток; у синхронного —
  приходит на потоке движка.
- Отмена кооперативная: `CancellationToken.cancel()` из любого потока;
  движок проверяет токен на следующем тике прогресса.
- **Пароль задаётся при открытии** (`Archive(path:password:)`), не при
  `extract`. Сменить пароль у уже открытого `Archive` нельзя — нужно
  открыть новый. То же со сменой кодировки (`encoding:`).

## 3. Слои приложения

Код приложения — в
`apps/macos/NewTheUnarchiver/NewTheUnarchiver/`. Четыре слоя плюс
отдельный таргет-расширение Quick Look.

### Domain (`Domain/`) — чистая модель, без UI и без движка

- `JobState.swift` — машина состояний задачи: `queued`, `running`,
  `needsPassword(PasswordReason)`, `needsEncoding(currentEncoding:)`,
  `succeeded(ExtractReport)`, `failed(ErrorCode)`, `cancelled`.
  `PasswordReason` различает `encrypted` / `wrongPassword` /
  `sharedDidNotMatch` (запомненный пароль не подошёл — для нейтральной
  подсказки вместо «красной ошибки»).
- `ArchiveJob.swift` — `@MainActor @Observable` одна задача: `url`,
  `state`, последний `Progress`, монотонный `overallFraction` (0…1 на
  весь архив, не прыжки per-entry), одноразовые `pendingPassword` /
  `pendingEncoding`, `destinationOverride`, токен отмены. Считает
  совокупный прогресс по смещениям файлов внутри архива.
- `AppModel.swift` — `@MainActor @Observable` корень: очередь `queue`
  (FIFO с дедупликацией по URL и отсевом папок), `sharedPassword`
  (только в памяти, для «Apply to All»), `extractionOptions`
  (персистится в `UserDefaults`), отложенное удаление завершённых строк.
- `ExtractionOptions.swift` — `nonisolated`, `Codable` value-тип:
  `WrapperMode` (`never` / `onlyIfMultiple` / `always`),
  `DestinationStrategy` (`nextToArchive` / `fixed(URL)` / `askEachTime`),
  `openFolderAfter`, `moveToTrashAfter`, `defaultEncoding`.

### Engine (`Engine/`) — оркестрация распаковки

- `Scheduler.swift` — `@MainActor` параллельный планировщик. Берёт из
  очереди совместимые задачи, держит до `maxParallel = min(CPU, 4)`
  активных, дозапускает по мере освобождения слотов. Разрешает пароль/
  кодировку/назначение для задачи. `submitPassword(applyToAll:)`
  раздаёт пароль всем ожидающим. Для тестов — `waitUntilQuiescent()`.
- `JobRunner.swift` — `@MainActor` исполнитель одной задачи: открыть
  `Archive`, получить список, посчитать число элементов верхнего уровня,
  разрешить папку назначения (предсоздать обёртку при `.always`),
  запустить `extract` на своей serial-`DispatchQueue`, поймать
  `encrypted`/`wrongPassword` → перевести в `needsPassword`, выполнить
  пост-действия при успехе, откатить пустую обёртку при ошибке.
- `CompatibilityPredicate.swift` — чистый предикат совместимости двух
  задач. Блокирует параллель, если любая задача на внешнем томе, на HDD
  (или `unknown` — трактуется консервативно), либо ждёт пароль.
- `VolumeProbe.swift` — `VolumeProbing` (протокол) + `SystemVolumeProbe`
  (`nonisolated`, кеш по mount-path под `OSAllocatedUnfairLock`).
  Классифицирует том SSD/HDD/unknown и internal/external. Эвристика
  пока слабая (см. §6).
- `ProgressThrottle.swift` — `nonisolated`, буферизация тиков прогресса
  до ~24 Гц, подавление одинаковых значений. `@unchecked Sendable`:
  безопасность гарантирует вызывающий (serial-очередь на задачу).
- `DestinationPrompter.swift` — протокол + реализация на `NSOpenPanel`
  (стратегия `.askEachTime`).
- `EncodingPreviewer.swift` — открывает архив с кандидатом кодировки и
  отдаёт первое имя файла для живого превью (без материализации всех
  записей).
- `EncodingPromptDebounce.swift` — чистая state-machine дебаунса ~200 мс
  для смены кодировки.
- `PostExtractActions.swift` — протокол + реализация: открыть папку в
  Finder, переместить архив в Корзину (`NSWorkspace`).
- `MacOSSidecars.swift` — `nonisolated`, единое правило «что движок молча
  отбрасывает»: `__MACOSX/`, `.DS_Store`, `._*` (case-sensitive).
- `SupportedFormats.swift` / `SupportedEncodings.swift` — единые списки
  форматов (для `File ▸ Open…`, `Info.plist`, вкладки Preferences) и
  кодировок (для inline-формы и Advanced). **Источник истины по
  конкретному перечню — эти файлы.**

### Views (`Views/`) — интерфейс очереди

- `QueueWindow.swift` — главное окно: drop-зона для URL, пустое
  состояние с подсказкой, список задач.
- `JobRowView.swift` — строка задачи: иконка, имя, подпись статуса,
  вспомогательный элемент (прогресс-бар / форма пароля / форма
  кодировки), кнопка отмены.
- `JobRowDisplay.swift` — чистая проекция `ArchiveJob` в поля UI
  (`SubtitleKind` для locale-независимых тестов).
- `PasswordPromptForm.swift` — `SecureField` + «Apply to All», подсказка
  зависит от `PasswordReason`.
- `EncodingPromptForm.swift` — `Picker` кодировок с живым превью и
  дебаунсом; `nil`-тег для авто-определения (не sentinel-строка).
- `FormatIcon.swift` — иконка по расширению через `NSWorkspace`,
  кеш на уровне приложения.
- `QueueWindowVisibility.swift` — чистая state-machine авто-скрытия окна
  при пустой очереди (реализована, в v1 окно фактически всегда видимо).

### Settings (`Settings/`) — Preferences (три вкладки)

- `SettingsScene.swift` — `Settings { TabView { … } }`, ⌘,.
- `ArchiveFormatsTab.swift` + `ArchiveFormatsModel.swift` — реальная
  ассоциация форматов через Launch Services, массовое назначение,
  бейджи текущего обработчика.
- `ExtractionTab.swift` — назначение (3 варианта), режим папки-обёртки
  (3 варианта), пост-действия.
- `AdvancedTab.swift` — глобальная кодировка по умолчанию.
- `FileAssociationsService.swift` — протокол + `LaunchServices`-реализация
  (`LSCopyDefaultRoleHandlerForContentType` /
  `LSSetDefaultRoleHandlerForContentType`), без App Sandbox.

### QuickLook — два направления

Встроенный рендер (`QuickLook/`):

- `PreviewInputEntry.swift` → `ArchiveTreeBuilder.swift` → `TreeNode.swift`
  — плоский список записей превращается в дерево папок; sidecar-пути
  отбрасываются по `MacOSSidecars`.
- `HTMLPreviewRenderer.swift` — чистый рендер дерева в HTML5 (все строки
  HTML-экранируются; иконки через `cid:`-ссылки; локализация EN+RU с
  множественными числами).
- `ExpansionPolicy.swift`, `ArchiveSummary.swift`, `IconCatalog.swift` —
  политика раскрытия папок, агрегат (файлы/папки/размер), сопоставление
  узлов с cid-иконками.

Таргет-расширение Finder (`../NewTheUnarchiverQuickLook/`):

- `PreviewProvider.swift` — `QLPreviewProvider`: открывает архив,
  строит дерево, рендерит HTML, прикладывает PNG-иконки. Зашифрованный
  архив → статичная страница; ошибка → generic-превью.
- `IconRenderer.swift` — `NSWorkspace` → PNG-байты для cid-иконок.
- У расширения **свой** `Localizable.xcstrings` (отдельный bundle).

## 4. Граф взаимодействий

```
AppCoordinator (фасад «пользователь открыл архивы»)
├─ AppModel ──── queue: [ArchiveJob] ── JobState / Progress / CancellationToken
│               ├─ ExtractionOptions (персистится в UserDefaults)
│               └─ sharedPassword (в памяти)
├─ Scheduler ── VolumeProbe ─ CompatibilityPredicate
│               ├─ PostExtractActions
│               └─ Task[] активных задач
│                  └─ JobRunner (на задачу)
│                     ├─ Archive (Newtua FFI)
│                     ├─ ProgressThrottle
│                     └─ serial DispatchQueue
├─ ArchiveFormatsModel ── FileAssociationsService ── Launch Services
└─ DestinationPrompter ── NSOpenPanel
```

Точка входа — `NewTheUnarchiverApp.swift`: окно очереди + сцена
Preferences. Все три способа открыть архив (drop, double-click /
open-with, `File ▸ Open…`) сходятся в один путь enqueue через
`AppCoordinator`.

## 5. Модель конкурентности

- `@MainActor`: `AppModel`, `ArchiveJob`, `Scheduler`, `AppCoordinator`,
  все View.
- На каждый `JobRunner` — приватная serial `DispatchQueue` (изоляция
  одного `Archive`).
- Прогресс из движка приходит на serial-очередь задачи →
  `ProgressThrottle` → хоп на главный поток для обновления UI.
- `nonisolated`-типы (движковая граница): `ExtractionOptions`,
  `MacOSSidecars`, `VolumeProbing`/`SystemVolumeProbe`, `ProgressThrottle`
  — чтобы не тянуть `@MainActor` через границу dynamic framework
  (см. Stage 10.1 в `plan.md`/`decisions.md`).

## 6. Известные ограничения v1 / задел на v2

Подтверждено журналом `decisions.md`:

- Состояние `.needsEncoding` реализовано и протестировано, но **в
  продакшене недостижимо** — движок не сигналит «имена выглядят
  подозрительно». Нужен триггер (кнопка «переоткрыть с кодировкой…»
  или новый код ABI).
- Нет переключателя «оставлять macOS-метаданные»: `ntua_extract`
  жёстко отбрасывает `__MACOSX/`, `._*`, `.DS_Store`. Чтобы дать опцию —
  нужен флаг в C-ABI (см. `apps/macos/CLAUDE.md` §8, §12).
- Эвристика `SystemVolumeProbe` слабая (внешние тома консервативно →
  serial). Точный детект через IOKit/Disk Arbitration отложен.
- Quick Look-расширение после установки требует ручной регистрации
  через `pluginkit` (последовательность — в `decisions.md`).
- `read`/`extract` синхронно и полностью буферизуют entry в память
  (лимит превью 100 МБ). Потоковое чтение — v2.
- Сборка только под Apple Silicon (`aarch64`). Universal — при
  необходимости через второй `--target` + `lipo` в build-скрипте.
- Дистрибуция (CI, нотаризация, hardened runtime) — после первого
  реального релиза.

## 7. Правила правок (кратко; полное — в `CLAUDE.md`)

- Нельзя править `crates/`, `Cargo.toml`, `Cargo.lock` — зона
  Rust-агента; правки движка оформляются как `docs/handoff-*.md`.
- Нельзя править `project.pbxproj` при открытом Xcode — для правок
  таргетов готовится пошаговая инструкция человеку.
- Сначала обсуждение, потом код. Все решения — в `decisions.md` с датой.
- Все пользовательские строки — в `Localizable.xcstrings`, RU+EN сразу.
- TDD-цикл из 10 подшагов; тесты только с тайм-аутами и серийно.
