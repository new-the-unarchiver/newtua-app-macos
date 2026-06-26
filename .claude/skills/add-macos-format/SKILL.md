---
name: add-macos-format
description: >-
  Use when bringing a new archive/compressor format that already exists in the
  Rust engine (newtua-core) into the macOS SwiftUI app — so Finder "Open With",
  double-click, and Quick Look recognise it. Covers the full cycle: diff
  engine-vs-app format sets, decide the UTI strategy, edit the OS-facing
  surfaces (SupportedFormats, Info.plist, Quick Look plist, localization,
  tests), run the test gate, build + install the pre-alpha via the install
  script, record the decision in decisions.md, and commit. Triggers:
  "добавь формат в приложение", "новый формат в macOS app", "add format to GUI",
  "advertise <ext> in the app", "появился формат в ядре".
---

# Добавление формата ядра в macOS-приложение

Движок (`crates/newtua-core`) уже умеет распаковывать формат — вся логика
детекта/распаковки там. **Задача приложения — только объявить формат системе**
(Finder «Открыть в программе», двойной клик, превью Quick Look). Никакой логики
архивов в Swift. Это и есть весь объём работы.

## Границы (нарушать нельзя)

- **`crates/`, `Cargo.toml`, `Cargo.lock` — только чтение.** Распаковка живёт в
  ядре; если формата в ядре ещё нет — это другая задача (Rust-агент), не эта.
- **`project.pbxproj` не править, если Xcode открыт** (`pgrep -x Xcode`).
  К счастью, для нового формата pbxproj обычно и не нужен: все правки идут в
  файлы, уже включённые в таргеты (Info.plist, `.xcstrings`, `.swift`). Если
  внезапно нужен новый файл в таргете — готовь инструкцию человеку, не правь
  pbxproj сам.
- **Все шаги и решения — в `decisions.md`** с датой ISO 8601.
- Пользовательские строки — в `Localizable.xcstrings`, **сразу RU + EN**.
- Отвечать человеку по-русски, простыми словами.

Преврати чек-лист ниже в todo-список и иди строго по нему.

## Фаза 0. Разведка состояния

1. Подтверди ветку и чистоту дерева: `git status`, `git branch --show-current`.
2. Прочитай хвост `apps/macos/NewTheUnarchiver/decisions.md`, `CLAUDE.md`,
   `ARCHITECTURE.md` — что уже сделано, нет ли наполовину сделанной работы.
3. **Сними дельту «ядро vs приложение»**:
   - Форматы ядра: `crates/newtua-core/src/archive.rs` (`enum FormatId`) +
     компрессоры `crates/newtua-core/src/decompress.rs` (`enum Compressor`) +
     расширения, которые ядро срезает: `detect.rs` (массив вида
     `&[".gz", ".bz2", ".xz", ".zst", ".Z", ".lz4"]`).
   - Что объявляет приложение:
     `NewTheUnarchiver/Engine/SupportedFormats.swift` (`static let formats`).
   - **Дельта** = форматы, которые ядро поддерживает, а приложение не объявляет.
     Это и есть список к добавлению.
4. Проверь, открыт ли Xcode: `pgrep -x Xcode && echo OPEN || echo closed`.

Дальше всё — на каждый формат из дельты.

## Фаза 1. Выбор стратегии UTI (ключевое решение)

У macOS либо уже есть системный UTI для расширения, либо нет. Проверь скриптом:

```bash
cat >/tmp/uti_probe.swift <<'EOF'
import UniformTypeIdentifiers
for ext in ["НОВЫЙ_EXT"] {            // напр. "lz4"
  if let t = UTType(filenameExtension: ext) {
    print("\(ext) -> \(t.identifier)  dynamic=\(t.isDynamic)")
  } else { print("\(ext) -> nil") }
}
EOF
swift /tmp/uti_probe.swift
```

- **Системный, `dynamic=false`** (как `lz4 -> public.lz4-archive`, `zst`, `lzma`,
  `z`): используй этот идентификатор напрямую. Импортированный UTI **не нужен** —
  это проще и надёжнее резолвится в тестовой среде.
- **`dynamic=true`** (как `ar`, `msi`, `udeb`) или `nil`: системного UTI нет.
  Заведи собственный импортированный UTI:
  `aleksei.trankov.newtheunarchiver.<имя>` — добавь его в
  `SupportedFormats.ImportedUTI` **и** в `UTImportedTypeDeclarations` Info.plist
  (см. готовые блоки `unix-ar`, `msi` как образец).
- Сверь, что выбранный идентификатор резолвится по строке:
  `UTType("<id>") != nil` (для системных — да; для импортированных в обычном
  процессе вернёт nil, но в `xcodebuild test` хост-приложение зарегистрировано и
  резолв проходит — это нормально, см. Фазу 3).

## Фаза 2. Правки OS-фасада (всё в один заход, синхронно)

Пять точек, которые не должны разъезжаться:

1. **`NewTheUnarchiver/Engine/SupportedFormats.swift`** — добавь
   `Format(utiIdentifier: "<uti>", extensions: ["<ext>", "tar.<ext>"])`
   (вторую запись — только если ядро понимает `tar.<ext>`). Ставь в логичную
   группу (компрессоры — рядом с gz/bz2/xz/zst/lzma/z).
2. **`NewTheUnarchiver/Info.plist`** — новый `<dict>` в `CFBundleDocumentTypes`
   (`CFBundleTypeName`, `CFBundleTypeRole=Viewer`, `LSHandlerRank=Default`,
   `LSItemContentTypes` → `<uti>`). Это даёт меню Finder и двойной клик.
   Если UTI собственный — добавь и `UTImportedTypeDeclarations`.
3. **`NewTheUnarchiverQuickLook/Info.plist`** — добавь `<uti>` в
   `QLSupportedContentTypes`. Это даёт превью Quick Look.
4. **`NewTheUnarchiver/Localizable.xcstrings`** — ключ `format.<ext>.name`
   (он выводится из `extensions[0]`), значения на `en` и `ru`,
   `"state": "translated"`. Скопируй структуру соседнего `format.*.name`.
5. **Тесты** `NewTheUnarchiverTests/Stage5Tests.swift` и `Stage7Tests.swift`:
   - подними оба хардкод-счётчика `SupportedFormats.formats.count == N`
     (их ровно два);
   - добавь `<ext>` (и `tar.<ext>`) в список `required` расширений (Stage5);
   - добавь `<uti>` в списки требуемых UTI (Stage5 `utTypes`, Stage7 `formats`).
   - `Stage7ExtendedTests` считать не надо — там счётчик выводится из реестра, но
     он требует, чтобы **каждый** UTI резолвился (`utTypes.count ==
     formats.count`). Системный UTI это обеспечивает; собственный — только если
     корректно объявлен в Info.plist.

Проверь артефакты до сборки:
```bash
cd apps/macos/NewTheUnarchiver
python3 -c "import json; d=json.load(open('NewTheUnarchiver/Localizable.xcstrings')); print('lz4' , 'format.<ext>.name' in d['strings'])"
plutil -lint NewTheUnarchiver/Info.plist NewTheUnarchiverQuickLook/Info.plist
```
(Диагностика SourceKit «No such module 'Testing'» в редакторе — ложная, это
индексатор вне сборки; настоящая проверка — сборка.)

## Фаза 3. Гейт: тесты до зелёного

Из `apps/macos/NewTheUnarchiver`. Сначала прогрей сборку (она дёргает Run Script
→ XCFramework), потом гоняй серийно с тайм-аутами (политика из `CLAUDE.md`):

```bash
killall -9 NewTheUnarchiver xcodebuild xctest 2>/dev/null; sleep 1
perl -e 'alarm 600; exec @ARGV' xcodebuild build-for-testing \
  -project NewTheUnarchiver.xcodeproj -scheme NewTheUnarchiver \
  -destination 'platform=macOS' -quiet 2>&1 | tail -5

killall -9 NewTheUnarchiver xcodebuild xctest 2>/dev/null; sleep 1
perl -e 'alarm 600; exec @ARGV' xcodebuild test-without-building \
  -project NewTheUnarchiver.xcodeproj -scheme NewTheUnarchiver \
  -destination 'platform=macOS' \
  -only-testing:NewTheUnarchiverTests \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 30 \
  -maximum-test-execution-time-allowance 60 \
  -parallel-testing-enabled NO \
  -resultBundlePath /tmp/xcresult-fmt -quiet 2>&1 | tail -6
xcrun xcresulttool get test-results summary --path /tmp/xcresult-fmt 2>&1 \
  | grep -E '"(passedTests|failedTests|result)"'
killall -9 NewTheUnarchiver xcodebuild xctest 2>/dev/null; rm -rf /tmp/xcresult-fmt
```

Должно быть `failedTests = 0`. Не двигаться дальше, пока не зелено.

## Фаза 4. Сборка продукта + установка

Всё делает скрипт `apps/macos/tools/install-prealpha.sh` (он собирает Release,
ставит в `/Applications`, регистрирует Launch Services + Quick Look, перезапускает
демонов и сам себя проверяет):

```bash
apps/macos/tools/install-prealpha.sh        # собрать Release + поставить
# или, если Release уже собран:
apps/macos/tools/install-prealpha.sh --no-build
```

Установка трогает систему пользователя (копия в `/Applications`, `killall
Finder`/`quicklookd`) — **спроси подтверждение перед запуском**, если человек
явно не просил ставить.

## Фаза 5. Проверка результата

Скрипт уже печатает две галочки (расширение включено в `/Applications`; новое
расширение резолвится в свой UTI). Дополнительно для уверенности:

```bash
# превью нового формата ведёт себя как заведомо рабочий .zip (нет ошибок)
qlmanage -p /путь/к/файлу.<ext> >/tmp/ql.log 2>&1 & sleep 5; kill %1 2>/dev/null
# единичный трейс ExtensionFoundation сразу после перезапуска демона — гонка,
# не ошибка; перезапусти и сравни с .zip. Варнинг про Cache.db безвреден.
```

## Фаза 6. Документация

Допиши в `apps/macos/NewTheUnarchiver/decisions.md` запись с датой ISO 8601:
что за формат(ы), выбранная стратегия UTI и почему, результат гейта
(`N passed, 0 failed`), что собрана/установлена пре-альфа, тронут ли pbxproj.
При изменении публичного поведения — обнови «Известные ограничения» в
`ARCHITECTURE.md` и при необходимости статус в `CLAUDE.md`.

## Фаза 7. Коммит и слияние с dev

Коммитим только когда человек попросил (он просит в рамках этой задачи).

```bash
git add <изменённые файлы под apps/macos/>
git commit -F - <<'MSG'
feat(gui): advertise <FORMAT> format (app + Quick Look + Finder)

<краткое тело: что добавлено, стратегия UTI, результат гейта>

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
MSG
```

Затем убедись, что изменения на `dev`. Практика проекта — коммитить прямо в
`dev` (вся gui-история линейна в `dev`). Если работа шла в отдельной ветке —
`git switch dev && git merge --no-ff <ветка>`. Пуш — только по явной просьбе.

## Памятка по образцам в коде

- Системный UTI без деклараций: `lz4` (`public.lz4-archive`), `zst`, `lzma`, `z`.
- Собственный импортированный UTI: `ar`, `msi` — см.
  `SupportedFormats.ImportedUTI` и `UTImportedTypeDeclarations` в Info.plist.
- `tar.<ext>` добавляется второй строкой в `extensions`, как у `tar.gz`/`tar.zst`.
- Рецепт регистрации Quick Look и почему `lsregister -f` не годится для `.appex`
  — `decisions.md`, запись «2026-06-24 — Регистрация QL extension».
