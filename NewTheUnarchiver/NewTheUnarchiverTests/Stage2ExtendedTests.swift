import Foundation
import Testing
import Newtua
@testable import NewTheUnarchiver

@MainActor
@Suite("Stage 2 — extended (engine queue)")
struct Stage2ExtendedTests {

    // MARK: - JobRunner — open/extract paths

    @Test("Runner succeeds on hello.rar (RAR path)")
    func runner_completes_rar() async throws {
        let app = AppModel()
        app.enqueue(urls: [TestSupport.fixture("hello.rar")])
        let job = try #require(app.queue.first)

        let dest = try TestSupport.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dest) }

        let runner = JobRunner(job: job, destination: dest)
        await runner.run()

        guard case .succeeded(let report) = job.state else {
            Issue.record("Expected .succeeded, got \(job.state)")
            return
        }
        #expect(report.extracted == 1)
    }

    @Test("Runner extracts a multi-entry archive (multi.7z) — 2 entries succeed")
    func runner_multiEntry_succeeds() async throws {
        let app = AppModel()
        app.enqueue(urls: [TestSupport.fixture("multi.7z")])
        let job = try #require(app.queue.first)

        let dest = try TestSupport.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dest) }

        let runner = JobRunner(job: job, destination: dest)
        await runner.run()

        guard case .succeeded(let report) = job.state else {
            Issue.record("Expected .succeeded, got \(job.state)")
            return
        }
        #expect(report.extracted == 2)
        // multi.7z has no shared root → wrapper folder "multi" is created.
        #expect(FileManager.default.fileExists(atPath: dest.appendingPathComponent("multi/f1.txt").path))
        #expect(FileManager.default.fileExists(atPath: dest.appendingPathComponent("multi/f2.txt").path))
    }

    @Test("Runner reports failure with .io for a missing archive")
    func runner_missingFile_failsIo() async throws {
        let app = AppModel()
        let bogus = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("no-such-\(UUID().uuidString).zip")
        app.enqueue(urls: [bogus])
        let job = try #require(app.queue.first)

        let dest = try TestSupport.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dest) }

        let runner = JobRunner(job: job, destination: dest)
        await runner.run()

        #expect(job.state == .failed(.io))
    }

    @Test("Runner reports needsPassword(.wrongPassword) when password is wrong")
    func runner_wrongPassword_setsState() async throws {
        let app = AppModel()
        app.enqueue(urls: [TestSupport.fixture("secret.7z")])
        let job = try #require(app.queue.first)

        let dest = try TestSupport.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dest) }

        let runner = JobRunner(job: job, destination: dest, password: "definitely-wrong")
        await runner.run()

        #expect(job.state == .needsPassword(.wrongPassword))
    }

    @Test("Runner succeeds on encrypted archive when correct password is supplied")
    func runner_correctPassword_succeeds() async throws {
        let app = AppModel()
        app.enqueue(urls: [TestSupport.fixture("secret.7z")])
        let job = try #require(app.queue.first)

        let dest = try TestSupport.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dest) }

        let runner = JobRunner(job: job, destination: dest, password: "pw")
        await runner.run()

        guard case .succeeded(let report) = job.state else {
            Issue.record("Expected .succeeded, got \(job.state)")
            return
        }
        #expect(report.extracted == 1)
    }

    // MARK: - ProgressThrottle — unit edges

    @Test("ProgressThrottle emits the first tick immediately, then respects the interval")
    func throttle_firstTick_emitsImmediately() {
        var now = Date(timeIntervalSinceReferenceDate: 100)
        let throttle = ProgressThrottle(intervalHz: 24, now: { now })
        #expect(throttle.feed(TestSupport.tick(bytes: 1)) != nil)
        // Same instant, different value → throttled by interval
        #expect(throttle.feed(TestSupport.tick(bytes: 2)) == nil)
        // Cross the interval → emits the next changed value
        now = Date(timeIntervalSinceReferenceDate: 100 + 1.0/24.0 + 0.001)
        #expect(throttle.feed(TestSupport.tick(bytes: 3)) != nil)
    }

    @Test("ProgressThrottle coalesces identical consecutive values (no-op suppression)")
    func throttle_identicalValues_coalesced() {
        var now = Date(timeIntervalSinceReferenceDate: 0)
        let throttle = ProgressThrottle(intervalHz: 24, now: { now })
        let p = TestSupport.tick(bytes: 5, of: 10)
        #expect(throttle.feed(p) != nil)
        // Past the interval, but value unchanged → still nil (no-op suppress).
        now = Date(timeIntervalSinceReferenceDate: 10)
        #expect(throttle.feed(p) == nil)
    }

    @Test("ProgressThrottle always emits started and finished ticks")
    func throttle_startedFinished_alwaysEmit() {
        var now = Date(timeIntervalSinceReferenceDate: 0)
        let throttle = ProgressThrottle(intervalHz: 24, now: { now })
        #expect(throttle.feed(TestSupport.tick(bytes: 0, of: 10, started: true)) != nil)
        now = Date(timeIntervalSinceReferenceDate: 0.001)
        #expect(
            throttle.feed(TestSupport.tick(bytes: 5, of: 10)) == nil,
            "mid tick within interval must be throttled"
        )
        now = Date(timeIntervalSinceReferenceDate: 0.002)
        #expect(
            throttle.feed(TestSupport.tick(bytes: 10, of: 10, finished: true)) != nil,
            "finished tick must always emit"
        )
    }

    @Test("ProgressThrottle.flush returns the latest buffered tick exactly once")
    func throttle_flush_returnsBuffered() {
        var now = Date(timeIntervalSinceReferenceDate: 0)
        let throttle = ProgressThrottle(intervalHz: 24, now: { now })
        let first = TestSupport.tick(bytes: 1, of: 100)
        let second = TestSupport.tick(bytes: 2, of: 100)
        _ = throttle.feed(first)
        now = Date(timeIntervalSinceReferenceDate: 0.001)
        #expect(throttle.feed(second) == nil)
        #expect(throttle.flush() == second)
        #expect(throttle.flush() == nil)
    }

    @Test("ProgressThrottle emits the buffered snapshot value when interval re-opens")
    func throttle_emitsLatestSnapshot_afterInterval() {
        var now = Date(timeIntervalSinceReferenceDate: 0)
        let throttle = ProgressThrottle(intervalHz: 24, now: { now })
        _ = throttle.feed(TestSupport.tick(bytes: 1, of: 100))
        now = Date(timeIntervalSinceReferenceDate: 0.001)
        #expect(throttle.feed(TestSupport.tick(bytes: 50, of: 100)) == nil)
        // Past interval — next feed emits the most recent value (latest).
        now = Date(timeIntervalSinceReferenceDate: 1.0)
        let c = TestSupport.tick(bytes: 75, of: 100)
        #expect(throttle.feed(c) == c)
    }
}
