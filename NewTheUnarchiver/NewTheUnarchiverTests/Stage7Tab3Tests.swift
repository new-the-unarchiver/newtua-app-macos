import Foundation
import Testing
@testable import NewTheUnarchiver

@MainActor
@Suite("Stage 7 — Preferences: Advanced tab (default encoding)")
struct Stage7Tab3Tests {

    // MARK: - defaultEncoding persistence (lives inside ExtractionOptions)

    @Test("ExtractionOptions: defaultEncoding survives Codable round-trip")
    func defaultEncoding_codable_roundtrip() throws {
        let original = ExtractionOptions(defaultEncoding: "shift_jis")
        let decoded = try JSONDecoder().decode(
            ExtractionOptions.self,
            from: JSONEncoder().encode(original)
        )
        #expect(decoded.defaultEncoding == "shift_jis")
    }

    @Test("ExtractionOptions: defaultEncoding defaults to nil (auto)")
    func defaultEncoding_defaultsToNil() {
        #expect(ExtractionOptions().defaultEncoding == nil)
    }

    // MARK: - Scheduler resolution

    @Test("Scheduler.resolvedEncoding: per-job pending wins over global default")
    func scheduler_resolvedEncoding_perJobWins() {
        let iso = TestSupport.isolatedDefaults()
        defer { iso.teardown() }
        let app = AppModel(defaults: iso.defaults)
        app.extractionOptions.defaultEncoding = "windows-1252"
        app.enqueue(urls: [URL(fileURLWithPath: "/tmp/x.zip")])
        let job = app.queue[0]
        job.attachPendingEncoding("cp866")
        let scheduler = Scheduler(model: app, probe: StubProbe(), maxParallel: 0)
        #expect(scheduler.resolvedEncoding(for: job) == "cp866")
    }

    @Test("Scheduler.resolvedEncoding: falls back to the global default when no per-job value")
    func scheduler_resolvedEncoding_globalFallback() {
        let iso = TestSupport.isolatedDefaults()
        defer { iso.teardown() }
        let app = AppModel(defaults: iso.defaults)
        app.extractionOptions.defaultEncoding = "windows-1251"
        app.enqueue(urls: [URL(fileURLWithPath: "/tmp/x.zip")])
        let job = app.queue[0]
        let scheduler = Scheduler(model: app, probe: StubProbe(), maxParallel: 0)
        #expect(scheduler.resolvedEncoding(for: job) == "windows-1251")
    }

    @Test("Scheduler.resolvedEncoding: nil + nil → nil (engine auto-detect)")
    func scheduler_resolvedEncoding_bothNil() {
        let iso = TestSupport.isolatedDefaults()
        defer { iso.teardown() }
        let app = AppModel(defaults: iso.defaults)
        app.enqueue(urls: [URL(fileURLWithPath: "/tmp/x.zip")])
        let job = app.queue[0]
        let scheduler = Scheduler(model: app, probe: StubProbe(), maxParallel: 0)
        #expect(scheduler.resolvedEncoding(for: job) == nil)
    }

    // MARK: - Scheduler.resolvedPassword (extracted alongside resolvedEncoding)

    @Test("Scheduler.resolvedPassword: per-job pending wins over sharedPassword")
    func scheduler_resolvedPassword_perJobWins() {
        let iso = TestSupport.isolatedDefaults()
        defer { iso.teardown() }
        let app = AppModel(defaults: iso.defaults)
        app.setSharedPassword("shared", applyToAll: true)
        app.enqueue(urls: [URL(fileURLWithPath: "/tmp/x.zip")])
        let job = app.queue[0]
        job.attachPendingPassword("specific")
        let scheduler = Scheduler(model: app, probe: StubProbe(), maxParallel: 0)
        #expect(scheduler.resolvedPassword(for: job) == "specific")
    }

    @Test("Scheduler.resolvedPassword: falls back to sharedPassword")
    func scheduler_resolvedPassword_sharedFallback() {
        let iso = TestSupport.isolatedDefaults()
        defer { iso.teardown() }
        let app = AppModel(defaults: iso.defaults)
        app.setSharedPassword("shared", applyToAll: true)
        app.enqueue(urls: [URL(fileURLWithPath: "/tmp/x.zip")])
        let job = app.queue[0]
        let scheduler = Scheduler(model: app, probe: StubProbe(), maxParallel: 0)
        #expect(scheduler.resolvedPassword(for: job) == "shared")
    }
}
