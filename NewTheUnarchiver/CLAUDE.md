# NewTheUnarchiver — бриф macOS GUI

Бриф для ассистента при работе над SwiftUI-приложением. Детали интеграции
с движком и контракт ядра — в родительских `CLAUDE.md` (ниже); здесь только
контекст приложения и то, чего там нет.

Xcode-проект: `NewTheUnarchiver.xcodeproj` в этой папке.

## Статус

**v1 готов** (2026-06-24, см. `decisions.md`). Фаза post-v1: поддержка,
мелкие правки, v2. Крупный скоуп — согласовать с человеком до кода.

## Связанные документы

| Файл | Зачем |
|------|--------|
| [`../CLAUDE.md`](../CLAUDE.md) | Линковка XCFramework, Swift API `Newtua`, concurrency, пароль, флаги `wrapper`/`strict`/`preserve`, расширение ABI. |
| [`../../../CLAUDE.md`](../../../CLAUDE.md) | Rust-движок: форматы, детект, extract, gotchas (`unrar`, in-process). |
| `decisions.md` | Журнал решений. **Перед задачей — свериться.** Новое — сюда с датой ISO. |
| `ARCHITECTURE.md` | Как устроен код (Domain / Engine / Views / Settings / QuickLook). |
| `plan.md` | История этапов 0–10.1; актуальность — в `decisions.md`. |
| `../.claude/skills/add-macos-format/` | Новый формат из ядра → UTI, Info.plist, QL, локализация, тесты, `install-prealpha.sh`. |
| `../tools/install-prealpha.sh` | Release в `/Applications` + Launch Services + Quick Look. |

## Стек

- SwiftUI, **macOS 26+**. Только `async`/`await` и `@Observable`; Combine не использовать.
- Логика архивов — в `Newtua` / `newtua-core` (см. [`../CLAUDE.md`](../CLAUDE.md)). В Swift — UI и оркестрация.

## Специфика приложения (не в родительских CLAUDE.md)

- **macOS metadata в UI:** движок дропает `._*`, `.DS_Store`, `__MACOSX/`; toggle нет
  (`decisions.md`). Подсчёт top-level — `Engine/MacOSSidecars.swift`, синхронно с движком.
- **Sandbox:** security-scoped bookmarks на destination — открыть scope **до** `extract`.
- **Папка-обёртка «Always»:** логика в Swift поверх `wrapper` (см. `decisions.md`).

## Запреты (macOS-агент)

- Править `crates/`, `Cargo.toml`, `Cargo.lock` — handoff Rust-агенту (`docs/handoff-*.md`).
- Править `project.pbxproj` при открытом Xcode — пошаговая инструкция пользователю.

Остальные запреты (subprocess, `unrar`, потоки `Archive` и т.д.) — в [`../CLAUDE.md`](../CLAUDE.md).

## Работа с человеком

- Сначала обсуждение, потом код. Коммит — только по явной просьбе.
- Ответы по-русски. Новые API SwiftUI/Apple — через `DocumentationSearch`.
- Решения, скоуп, отказы — сразу в `decisions.md`.

## Локализация (RU + EN)

От движка — только `NewtuaError.message`. Всё UI — **String Catalog**
`Localizable.xcstrings`: ключи в RU и EN одновременно с кодом; SwiftUI —
`Text("key")`, иначе `String(localized:)`. Без хардкода. Plural — variations.

## Тесты

TDD: тесты первыми → минимальный код → зелёные → расширенный набор (unit/integration/end-to-end/edge) → ревью → зелёные.

- Unit/integration: **Swift Testing** (`@Test`, `#expect`).
- UI: **XCUIAutomation** (`NewTheUnarchiverUITests`).
- Обёртка `Newtua`: `swift test` в `bindings/swift/` (сначала XCFramework — см. [`../CLAUDE.md`](../CLAUDE.md)).
- Сборка: MCP `BuildProject`; диагностика: `XcodeRefreshCodeIssuesInFile`.

**Каждый** `xcodebuild test` — **тайм-ауты**, серийно, killall до и после:

```bash
killall -9 NewTheUnarchiver xcodebuild xctest 2>/dev/null; sleep 1
perl -e 'alarm 240; exec @ARGV' xcodebuild test \
  -project NewTheUnarchiver.xcodeproj -scheme NewTheUnarchiver \
  -destination 'platform=macOS' \
  -only-testing:NewTheUnarchiverTests/<suite> \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 30 \
  -maximum-test-execution-time-allowance 60 \
  -parallel-testing-enabled NO \
  -resultBundlePath /tmp/xcresult-<name> -quiet 2>&1 | tail -3
xcrun xcresulttool get test-results summary --path /tmp/xcresult-<name> \
  2>&1 | grep -E '"(passedTests|failedTests|result)"' | head -3
killall -9 NewTheUnarchiver xcodebuild xctest 2>/dev/null
```

`-parallel-testing-enabled NO` — стабильнее с MainActor. Внешний пояс — `perl alarm`.

## Code Index

CLI-индексатор вместо grep/find (`--path` = корень репо): `query`, `search-function`,
`get-callers`, `get-file-summary`, `stats` — все с `--json`. Read-only БД, параллельно с MCP.
