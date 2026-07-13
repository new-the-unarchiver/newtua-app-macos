# newtua — macOS GUI (технический контракт)

Технический контракт интеграции SwiftUI-приложения с Rust-движком. Продуктовый
контекст, процесс работы, решения и карта кода — в
`NewTheUnarchiver/CLAUDE.md`, `decisions.md`, `ARCHITECTURE.md`. Контракт
ядра (форматы, детект, extract) — в корневом `CLAUDE.md`.

---

## Граница ответственности

**В Swift — только UI и оркестрация.** Детект, листинг, декомпрессия, пароли,
кодировки, path-safety, symlinks, права и mtime — в Rust (`newtua-core`) через
пакет `Newtua`. Парсить байты архивов или считать пути извлечения в Swift
нельзя.

Приложение **только распаковывает и листит**, архивы не создаёт.

---

## География репозитория

Xcode-проект: `apps/macos/NewTheUnarchiver/NewTheUnarchiver.xcodeproj`
(`SRCROOT` = `apps/macos/NewTheUnarchiver`). Корень репо — через
`git rev-parse --show-toplevel`, не хардкод `../../..`.

| Путь | Назначение |
|------|------------|
| `bindings/swift/` | Локальный SwiftPM-пакет `Newtua` (обёртка C ABI) |
| `crates/newtua-ffi/` | Rust C-ABI; заголовок `include/newtua.h` (cbindgen) |
| `crates/newtua-core/` | Движок — из Swift не трогаем |
| `apps/macos/tools/build-newtua-xcframework.sh` | Сборка `Newtua.xcframework` |

Пакет `Newtua` можно расширять для удобного Swift API. Правки Rust/ABI — только
если UI реально упирается в пробел C ABI (см. ниже); иначе — handoff Rust-агенту.

---

## Линковка движка

Движок линкуется через **XCFramework**, не через `target/debug/libnewtua_ffi.a`.

1. Скрипт `apps/macos/tools/build-newtua-xcframework.sh` собирает release
   `cdylib` (`aarch64-apple-darwin`) и кладёт `bindings/swift/Newtua.xcframework`.
   XCFramework в git не коммитим.
2. `bindings/swift/Package.swift` — `.binaryTarget(name: "CNewtua", …)`;
   продукт `Newtua` — dynamic library для Embed & Sign.
3. В Xcode — Run Script **до** Compile Sources (скрипт сам early-exit по mtime).
   `PATH` должен включать `~/.cargo/bin` — иначе `cargo: command not found`.
4. App target — Newtua **Embed & Sign**. Quick Look extension — **Do Not Embed**
   (читает framework из app bundle через `@rpath`).
5. Пакет добавлять **локально** (File ▸ Add Package Dependencies ▸ Add Local… →
   `bindings/swift`). Remote-пакет с binary target здесь не нужен.

`swift test` в `bindings/swift` **не** вызывает cargo — сначала собрать
XCFramework (скриптом или сборкой app в Xcode).

---

## Swift API (`import Newtua`)

Публичная поверхность — Swift-native, без `import CNewtua` в приложении:

```swift
func version() -> String

enum ErrorCode { case io, unknownFormat, unsupported, encrypted, wrongPassword,
                 corrupt, pathTraversal, missingVolume, invalidIndex, nullArg, utf8, panic }
struct NewtuaError: Error { let code: ErrorCode; let message: String }

enum EntryKind { case file, dir, symlink }
struct Entry { let path: String; let kind: EntryKind; let size: UInt64
              let isEncrypted: Bool; let mode: UInt32?; let mtime: Int64? }

struct Progress { let index: Int; let path: String?; let bytesWritten: UInt64
                 let entrySize: UInt64; let started: Bool; let finished: Bool }
struct ExtractReport { let extracted: UInt64; let failed: UInt64; let aborted: Bool }
final class CancellationToken { var isCancelled: Bool; func cancel() }

final class Archive {
    init(path: String, password: String? = nil, encoding: String? = nil) throws
    var count: Int
    func entries() -> [Entry]
    func entry(at index: Int) -> Entry?
    func read(_ index: Int) throws -> Data
    func read(_ index: Int) async throws -> Data
    func extract(to dest: String, selection: [Int]? = nil,
                 wrapper: Bool = true, strict: Bool = false, preserve: Bool = true,
                 cancellation: CancellationToken? = nil,
                 progress: ((Progress) -> Void)? = nil) throws -> ExtractReport
    func extract(…same params…) async throws -> ExtractReport  // progress → MainActor
}
```

**Память и безопасность:** `Archive` освобождает handle в `deinit`; `Entry` и
`Data` из `read` — копии. Rust panic не пересекает границу — только
`NewtuaError`.

**Производительность:** `read` грузит entry целиком (нет streaming v1).
`entries()` каждый раз строит массив — кешировать в view model.

---

## Конкурентность

- **`Archive` не потокобезопасен** — один экземпляр, один поток/очередь.
- Sync-методы блокируют вызывающий поток; **async**-варианты сериализуются на
  внутренней очереди пакета.
- Async `extract`: progress приходит на **MainActor** автоматически. Sync
  `extract`: callback на потоке движка — не трогать SwiftUI напрямую.
- Отмена — `CancellationToken.cancel()`; cooperative, проверяется на тиках
  progress. `ExtractReport.aborted == true` при abort.

---

## Ошибки и пароль

`NewtuaError.code` — что случилось; `.message` — локализованная строка
(EN/RU из движка, передавать `Locale.current.identifier` где API это поддерживает).

| Код | UI |
|-----|-----|
| `.encrypted` / `.wrongPassword` | Запрос пароля |
| `.unknownFormat` | Не архив / не поддерживается |
| `.corrupt` | Повреждённый архив |
| `.pathTraversal` | Только при `strict: true`; иначе entry пропускается |

**Пароль задаётся при открытии**, не при extract. Зашифрованный архив: открыть
без пароля → prompt → **новый** `Archive(path:password:)`. Добавить пароль к
уже открытому `Archive` нельзя.

---

## Имена и кодировки

`Entry.path` — уже UTF-8 (движок детектит charset по всем именам сразу).
Override — `Archive(path:encoding:)` (`"shift_jis"`, `"cp866"`, …, метки
WHATWG/`encoding_rs`); смена требует переоткрытия.

---

## Флаги движка (не переimplementировать)

- **`wrapper`** — «Create enclosing folder»: если нет общего top-level каталога,
  оборачивает в папку по stem архива; если есть — не добавляет лишнего.
- **`strict`** — zip-slip abort; иначе unsafe entries пропускаются.
- **`preserve: true`** (default) — symlinks, mode, mtime на диске.

**macOS metadata** (`._*`, `.DS_Store`, `__MACOSX/`) движок **пропускает по
умолчанию**. C ABI пока без `keep_macos_metadata` (всегда skip). В GUI toggle
нет (см. `decisions.md`). Для подсчёта top-level items в UI дублируем правило
в `MacOSSidecars.swift`, синхронно с движком.

---

## Зона Swift (движок не покрывает)

- Drag & drop, Open With, UTIs в Info.plist.
- App Sandbox: `com.apple.security.files.user-selected.read-write`;
  security-scoped bookmarks для destination между запусками — открыть scope
  **до** `extract`, закрыть после.
- Hardened Runtime / notarization для дистрибуции вне App Store.

---

## Расширение ABI (редко)

Если UI нужно то, чего нет в C ABI (toggle metadata, streaming read, failed
paths в report):

1. `crates/newtua-ffi/src/lib.rs` — `extern "C"`, `catch_unwind`, `NtuaStatus`.
2. `cargo build -p newtua-ffi` → пересборка XCFramework.
3. `bindings/swift/Sources/Newtua/Newtua.swift` → `swift test`.
4. Строки локализуются во front-end, не в core.

Известные пробелы ABI: нет `keep_macos_metadata`; `ExtractReport` — только
счётчики, без путей ошибок.

---

## Сборка и smoke-test

```sh
# XCFramework (или просто собрать app в Xcode — Run Script сделает сам)
apps/macos/tools/build-newtua-xcframework.sh

cd bindings/swift && swift test
```

Smoke: `crates/newtua-core/tests/fixtures/hello.7z` — один entry `a.txt`,
extract во temp, файл на месте.

---

## Запреты

- Логика архивов, path-safety, subprocess к `rar`/`7z`/`tar` — всё in-process
  в dylib.
- Main thread для sync `extract`/`read` больших архивов.
- Один `Archive` с нескольких потоков.
- Править `crates/`, `Cargo.toml`, `Cargo.lock` из macOS-агента — handoff
  Rust-агенту.
- `cargo update unrar` / трогать `vendor/unrar-0.5.8` (см. корневой CLAUDE.md).

## Code Index — быстрый поиск по коду

Для поиска по коду используй CLI-индексатор вместо grep/find/Read:
- Поиск: code-index query "имя" --path /путь/к/проекту --json
- FTS поиск: code-index search-function "запрос" --path /путь/к/проекту
- Граф вызовов: code-index get-callers "функция" --path /путь/к/проекту
- Карта файла: code-index get-file-summary "файл" --path /путь/к/проекту
- Статистика: code-index stats --path /путь/к/проекту --json
Все команды выводят JSON. Это мгновенный поиск по индексированной базе.

> **Примечание:** Read-команды CLI открывают БД в режиме `SQLITE_OPEN_READ_ONLY`, поэтому работают параллельно с MCP-демоном без блокировок.
