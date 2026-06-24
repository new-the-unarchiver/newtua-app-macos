---
дата: 2026-06-24
автор: ассистент macOS GUI (предыдущая сессия)
адресат: ассистент macOS GUI (следующая сессия)
тема: починить 6 warnings про main-actor isolation, появившиеся после
      перехода Newtua на dynamic library (Этап 10)
---

# Задача: устранить 6 strict-concurrency warnings

## Контекст

На Этапе 10 (XCFramework + Release-распространение) Newtua-обёртка из
`bindings/swift/` переведена с `.staticLibrary` (через `unsafeFlags`)
на `.dynamic` `.library` с binaryTarget XCFramework. См.
`decisions.md` за 2026-06-24, секцию «Этап 10».

После этой миграции при сборке `NewTheUnarchiver` Xcode выдаёт 6
warnings из Swift 6 strict-concurrency проверки. Все из них — в нашем
коде (`apps/macos/NewTheUnarchiver/NewTheUnarchiver/`), но триггер
сменился именно с этапом 10: до него `XcodeListNavigatorIssues`
возвращал пусто. Гипотеза: переход на dynamic-link через framework
сделал видимыми те protocol-уровневые isolation-атрибуты, которые
раньше инлайнились компилятором и проверка их пропускала.

**Это не блокер v1.** Все тесты зелёные (NewTheUnarchiverTests 241/241,
UITests 4/4, swift test 20/20, BuildProject Debug+Release без errors).
Но прежде чем закрывать v1, человек хочет, чтобы warnings были
устранены — это финальный полиш качества сборки.

## Точный список warnings

(полученный через `XcodeListNavigatorIssues severity=warning` сразу
после успешной BuildProject Debug-сборки)

```
1. Engine/JobRunner.swift:31
   Call to main actor-isolated initializer
   'init(wrapperMode:destinationStrategy:openFolderAfter:moveToTrashAfter:defaultEncoding:)'
   in a synchronous nonisolated context
   → строка: `options: ExtractionOptions = ExtractionOptions(),`

2. Engine/JobRunner.swift:109
   Call to main actor-isolated instance method 'feed'
   in a synchronous nonisolated context
   → строка: `guard let emit = throttle.feed(p), !token.isCancelled`

3. Engine/JobRunner.swift:116
   Call to main actor-isolated instance method 'flush'
   in a synchronous nonisolated context
   → строка: `if let tail = throttle.flush(), !token.isCancelled {`

4. Engine/JobRunner.swift:188
   Call to main actor-isolated static method 'matches'
   in a synchronous nonisolated context
   → строка: `if MacOSSidecars.matches(first) { continue }`
   (внутри `nonisolated static func topLevelItemCount`)

5. Engine/Scheduler.swift:32
   Call to main actor-isolated initializer 'init()'
   in a synchronous nonisolated context
   → строка: `probe: VolumeProbing = SystemVolumeProbe(),`

6. QuickLook/ArchiveTreeBuilder.swift:23
   Call to main actor-isolated static method 'matches'
   in a synchronous nonisolated context
   → строка: `if components.contains(where: MacOSSidecars.matches) { return }`
```

## Архитектурная причина (моё прочтение)

Корни лежат в **двух типах**, у которых @MainActor вывелся неявно:

**a) `MacOSSidecars` (Engine/MacOSSidecars.swift)** — это `enum` с двумя
   static-функциями `matches(String)` и `matches(Substring)`. Сам по
   себе он не помечен @MainActor, но компилятор выводит ему main-actor
   isolation скорее всего через ⤵
   - либо `defaultIsolation = MainActor` на уровне модуля (см. Swift
     6.2 / SwiftSettings),
   - либо через какой-то protocol conformance в соседнем коде, которая
     заражает enum.
   Затронутые callers — все nonisolated (JobRunner.topLevelItemCount,
   ArchiveTreeBuilder, JobRunner-extract-callback).

**b) `VolumeProbing` (Engine/VolumeProbe.swift:15)** — protocol,
   inheriting main-actor isolation. Об этом прямо говорит note из
   Xcode:
   `main actor isolation inferred from conformance to protocol
   'VolumeProbing'`.
   Из-за этого `SystemVolumeProbe.init()` тоже main-actor isolated, и
   default-параметр в `Scheduler.init` — nonisolated context — не
   может его вызвать.

**c) `ExtractionOptions` (Domain/ExtractionOptions.swift, не прочитан
   в этом handoff)** — там вероятно тот же сценарий: тип или его
   `init` помечен/выведен как main-actor isolated, и default-параметр
   в `JobRunner.init` его не может вызвать.

**d) `ProgressThrottle` (Engine/ProgressThrottle.swift)** —
   `final class ... : @unchecked Sendable`. Без явного @MainActor.
   Но методы `feed`/`flush` помечены как main-actor isolated —
   скорее всего, через тот же defaultIsolation механизм. Вызываются из
   nonisolated DispatchQueue-callback внутри `archive.extract`'s
   `progress:` closure (JobRunner.swift:106-120).

## Что важно НЕ сломать при исправлении

1. **Поведение `Archive.extract`'s `progress:` callback.** Сейчас он
   вызывается на extraction-thread (не на main), и наш код в JobRunner
   именно туда сбрасывает throttle, чтобы UI обновлялся «не чаще 24
   Hz», а уже потом `DispatchQueue.main.async` хопит результат на
   main. Это сознательная архитектура (см. `apps/macos/CLAUDE.md §4`
   «Concurrency») — её ломать нельзя. ProgressThrottle обязан быть
   доступен **с фонового потока** без MainActor-prefix.

2. **`topLevelItemCount` помечен `nonisolated static`** на
   JobRunner:182 сознательно — он вызывается из тестов и не должен
   требовать main-actor. Если поменять MacOSSidecars так, чтобы вызов
   `matches` стал MainActor — этот метод сломается.

3. **`SystemVolumeProbe` создаётся как default-параметр в
   `Scheduler.init`** — Scheduler в свою очередь создаётся из
   `@MainActor`-окружения (AppModel/SwiftUI app entry). Но
   default-параметры в Swift всегда вычисляются в контексте caller'а,
   и формально SwiftPM/Swift 6 это считает «nonisolated» местом.
   Поэтому либо тип нужно сделать nonisolated, либо явный
   `MainActor.assumeIsolated` обёртку, либо лениво создавать probe в
   теле init.

4. **Все 241 теста NewTheUnarchiverTests и 4 теста UITests должны
   остаться зелёными.** Существующие исоляции в тестах рассчитаны на
   текущее поведение типов.

5. **Newtua-обёртка (`bindings/swift/`) — НЕ трогать.** Она только что
   стала dynamic library, всё сейчас в правильном состоянии. Если
   что-то кажется, что нужно править в Newtua-обёртке, это сигнал
   неверного подхода.

6. **Cargo / Rust-ядро / Newtua C-ABI — категорически не трогать.**
   См. `MEMORY.md` (memory `feedback_dont_edit_cargo_toml.md`).

## Возможные подходы (выбирать осознанно, не наугад)

### Подход A — пометить типы явно как `nonisolated`

Самый локальный fix:

```swift
nonisolated enum MacOSSidecars { ... }       // в Engine/MacOSSidecars.swift
nonisolated protocol VolumeProbing: Sendable { ... }  // VolumeProbe.swift:15
nonisolated final class SystemVolumeProbe: VolumeProbing, @unchecked Sendable {
    nonisolated init() {}
    ...
}
nonisolated final class ProgressThrottle: @unchecked Sendable {
    nonisolated init(...) { ... }
    nonisolated func feed(_ p: Newtua.Progress) -> Newtua.Progress? { ... }
    nonisolated func flush() -> Newtua.Progress? { ... }
}
```

Для `ExtractionOptions` — прочитать его файл, понять где источник
isolation, и пометить `nonisolated`.

**Плюс:** минимальная инвазивность.
**Минус:** придётся пройтись по 4-5 типам.

### Подход B — настроить `defaultIsolation = nil` на уровне targets

Если в проекте где-то стоит `defaultIsolation = MainActor` (через
`SwiftSettings.defaultIsolation` или `-default-isolation MainActor`
linker flag), то конкретно для `NewTheUnarchiver`-таргета сменить
на nonisolated и помечать `@MainActor` явно там, где это реально
нужно (Views, Observable models).

Это **архитектурно правильный** путь для приложений, у которых есть
много background-логики: явная MainActor лучше неявной. Но требует
понимания, где сейчас включён неявный MainActor, и аккуратной правки
проектных настроек.

**Проверить:** есть ли в `project.pbxproj` или в build settings
`SWIFT_DEFAULT_ISOLATION` / `SWIFT_UPCOMING_FEATURE_*` /
`SWIFT_STRICT_CONCURRENCY` ? Если да — это и есть рычаг. **НО**
менять build settings — это правка pbxproj, которая запрещена при
открытом Xcode (см. `MEMORY.md`/`feedback_no_pbxproj_edits.md`).
Соответственно — описать ручную правку для пользователя.

### Подход C — точечные `MainActor.assumeIsolated` обёртки

В местах вызова обернуть в `MainActor.assumeIsolated { ... }`. Это
работает, но это «затыкание» — оно не решает архитектурную причину
isolation drift'а, и потом такой же warning всплывёт в новом месте.

**Не рекомендую.** Это худший подход — он скрывает корень проблемы.

## Рекомендуемый порядок действий

1. **Прочитать `Domain/ExtractionOptions.swift`** и понять, откуда
   там main-actor isolation. Скорее всего, тот же defaultIsolation
   механизм.
2. **Найти источник `defaultIsolation`.** Грепнуть проект на
   `defaultIsolation`, `@MainActor` на уровне модуля, `SwiftSettings`
   в `Package.swift` если есть. Если нашли — Подход B становится
   реалистичным. Если нет — почему `VolumeProbing` помечается
   MainActor «сам по себе»? Прочитать ошибку Xcode полностью через
   `XcodeListNavigatorIssues` — она содержит note о причине.
3. **Принять решение между A и B**, зафиксировать в `decisions.md`
   (новая секция «2026-XX-XX — Stage 10.1: устранение strict-concurrency
   warnings»).
4. **TDD-первым:** написать тесты, проверяющие, что:
   - `MacOSSidecars.matches` вызывается из background-thread
     корректно.
   - `ProgressThrottle.feed/flush` корректно работает из
     non-MainActor-контекста (имитировать через `Task.detached`).
   - `SystemVolumeProbe.init()` вызывается из background.
   Эти тесты сейчас скорее всего проходят, но фиксируют контракт.
5. **Применить fix**.
6. **Проверка:**
   - `XcodeListNavigatorIssues severity=warning` после BuildProject
     должен быть пустым.
   - `NewTheUnarchiverTests` — 241/241 зелёные.
   - `NewTheUnarchiverUITests` — 4/4 зелёные.
   - BuildProject Debug — 0 errors, 0 warnings.
   - BuildProject Release — 0 errors, 0 warnings.
7. **Коммит** (по правилу `feedback_commits_per_stage.md` после
   завершения этапа сразу делаем git-коммит).

## Файлы, которые надо прочитать перед началом

- `Engine/MacOSSidecars.swift` — 23 строки, целиком.
- `Engine/VolumeProbe.swift` — 83 строки, целиком.
- `Engine/ProgressThrottle.swift` — целиком.
- `Engine/JobRunner.swift` — целиком (вызовы из nonisolated контекста).
- `Engine/Scheduler.swift:30-50` — init с default-параметром probe.
- `Domain/ExtractionOptions.swift` — целиком, чтобы понять origin
  isolation.
- `QuickLook/ArchiveTreeBuilder.swift:20-45` — функция `insert`.
- `apps/macos/CLAUDE.md §4` — концепция concurrency, чтобы не сломать
  «прогресс на extraction-thread, потом hop в main».

## Что я (предыдущая сессия) уже проверил

- Все 6 warnings проявляются и в Debug, и в Release — то есть это
  не зависит от конфигурации.
- Сборка успешна, тесты зелёные. То есть **семантика правильная**,
  компилятор просто не может это формально доказать с текущей
  isolation-аннотацией.
- В `bindings/swift/` ничего трогать не нужно — все 20 swift-test
  зелёные без изменений.

## Критерий завершения

- `XcodeListNavigatorIssues` (severity=warning) после полной сборки
  Debug и Release возвращает 0 issues.
- Все 245 тестов (241 + 4 UI) остаются зелёными.
- Запись в `decisions.md` с обоснованием выбранного подхода.
- Git-коммит.
- Пользователю передаётся работа обратно с сообщением «warnings
  устранены, v1 готов записывать».
