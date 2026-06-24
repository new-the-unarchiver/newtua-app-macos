import Foundation
import Testing
import Newtua
@testable import NewTheUnarchiver

/// Stage 10.1 — после Этапа 10 (Newtua → dynamic framework) компилятор
/// под `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` начал требовать явных
/// `nonisolated`-аннотаций на «движковых» типах. Эти тесты фиксируют, что
/// движковые типы остаются вызываемыми вне main-actor.
///
/// «Красная» форма этих тестов — не failure runtime, а warning в
/// `XcodeListNavigatorIssues` (см. handoff-2026-06-24-mainactor-warnings.md).
/// Правки сводят warning'и к нулю; runtime-проверки ниже гарантируют,
/// что семантика не сломалась.
@Suite("Stage 10.1 — engine types stay callable off the main actor")
struct Stage10ConcurrencyTests {

    // MARK: - MacOSSidecars

    @Test
    nonisolated func macOSSidecarsMatchesIsCallableFromNonisolated() {
        #expect(MacOSSidecars.matches("__MACOSX"))
        #expect(MacOSSidecars.matches(".DS_Store"))
        #expect(MacOSSidecars.matches("._foo"))
        #expect(!MacOSSidecars.matches("regular"))
        let sub: Substring = "._bar"[...]
        #expect(MacOSSidecars.matches(sub))
    }

    @Test
    func macOSSidecarsMatchesWorksFromDetachedTask() async {
        let hit = await Task.detached {
            MacOSSidecars.matches("__MACOSX")
        }.value
        #expect(hit)
    }

    // MARK: - ExtractionOptions

    @Test
    nonisolated func extractionOptionsDefaultInitIsCallableFromNonisolated() {
        let opts = ExtractionOptions()
        #expect(opts.wrapperMode == .onlyIfMultiple)
        #expect(opts.destinationStrategy == .nextToArchive)
        #expect(opts.openFolderAfter == false)
        #expect(opts.moveToTrashAfter == false)
        #expect(opts.defaultEncoding == nil)
    }

    @Test
    nonisolated func extractionOptionsResolveURLIsCallableFromNonisolated() {
        let opts = ExtractionOptions(wrapperMode: .always)
        let base = URL(fileURLWithPath: "/tmp/dest")
        let archive = URL(fileURLWithPath: "/tmp/box.zip")
        let resolved = opts.resolvedExtractURL(base: base, archive: archive, topLevelCount: 1)
        #expect(resolved.lastPathComponent == "box")
    }

    // MARK: - ProgressThrottle

    @Test
    func progressThrottleFeedAndFlushFromDetachedTask() async {
        let started = TestSupport.tick(bytes: 0, of: 100, started: true)
        let mid = TestSupport.tick(bytes: 50, of: 100)
        let result = await Task.detached { () -> (Newtua.Progress?, Newtua.Progress?, Newtua.Progress?) in
            // Frozen clock at t=100s — guarantees the second feed is
            // dropped by the 24 Hz interval window, then surfaces on flush.
            let throttle = ProgressThrottle(
                intervalHz: 24,
                now: { Date(timeIntervalSince1970: 100) }
            )
            let a = throttle.feed(started)
            let b = throttle.feed(mid)
            let c = throttle.flush()
            return (a, b, c)
        }.value
        #expect(result.0 != nil)
        #expect(result.1 == nil)
        #expect(result.2 == mid)
    }

    // MARK: - VolumeProbing / SystemVolumeProbe

    @Test
    func systemVolumeProbeInitAndMethodsFromDetachedTask() async {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
        let medium = await Task.detached { () -> VolumeMediumType in
            let probe = SystemVolumeProbe()
            _ = probe.isInternal(url)
            return probe.mediumType(url)
        }.value
        #expect([VolumeMediumType.ssd, .hdd, .unknown].contains(medium))
    }

    @Test
    nonisolated func volumeProbingCanBeAdoptedByNonisolatedType() {
        struct AlwaysHDD: VolumeProbing {
            func isInternal(_ url: URL) -> Bool { true }
            func mediumType(_ url: URL) -> VolumeMediumType { .hdd }
        }
        let probe = AlwaysHDD()
        let url = URL(fileURLWithPath: "/")
        #expect(probe.isInternal(url))
        #expect(probe.mediumType(url) == .hdd)
    }
}
