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

        guard case .failed(let code) = job.state else {
            Issue.record("Expected .failed, got \(job.state)")
            return
        }
        // Engine maps missing file to either Io or UnknownFormat depending on
        // when the open path discovers the absence. Both are acceptable.
        #expect(code == .io || code == .unknownFormat)
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

    // MARK: - QueueDriver — sequential drain

    @Test("QueueDriver drains an empty queue without error")
    func driver_emptyQueue_noop() async {
        let app = AppModel()
        let driver = QueueDriver(model: app)
        await driver.drain()
        #expect(app.queue.isEmpty)
    }

    @Test("QueueDriver runs queued jobs sequentially")
    func driver_runsAllJobs_sequentially() async throws {
        // Copy fixtures into a writable temp dir so the default "next to
        // archive" destination strategy lands inside our sandbox-friendly tmp.
        let tmp = try TestSupport.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let h7z = tmp.appendingPathComponent("hello.7z")
        let hrar = tmp.appendingPathComponent("hello.rar")
        try FileManager.default.copyItem(at: TestSupport.fixture("hello.7z"), to: h7z)
        try FileManager.default.copyItem(at: TestSupport.fixture("hello.rar"), to: hrar)

        let app = AppModel()
        app.enqueue(urls: [h7z, hrar])
        #expect(app.queue.count == 2)

        let driver = QueueDriver(model: app)
        await driver.drain()

        for job in app.queue {
            if case .succeeded = job.state { continue }
            Issue.record("Job \(job.url.lastPathComponent) not in .succeeded: \(job.state)")
        }
    }

    @Test("QueueDriver skips jobs already in a terminal state")
    func driver_skipsTerminalJobs() async throws {
        let app = AppModel()
        app.enqueue(urls: [TestSupport.fixture("hello.7z")])
        let pre = try #require(app.queue.first)
        // Pre-mark the only job as cancelled — driver should leave it alone.
        pre.cancel()
        #expect(pre.state == .cancelled)

        let driver = QueueDriver(model: app)
        await driver.drain()

        #expect(pre.state == .cancelled)
    }

    // MARK: - ProgressThrottle — unit edges

    @Test("ProgressThrottle emits the first tick immediately, then respects the interval")
    func throttle_firstTick_emitsImmediately() {
        var now = Date(timeIntervalSinceReferenceDate: 100)
        let throttle = ProgressThrottle(intervalHz: 24, now: { now })
        let p1 = Newtua.Progress(
            index: 0, path: "a", bytesWritten: 1,
            entrySize: 1000, started: false, finished: false
        )
        let p2 = Newtua.Progress(
            index: 0, path: "a", bytesWritten: 2,
            entrySize: 1000, started: false, finished: false
        )
        let p3 = Newtua.Progress(
            index: 0, path: "a", bytesWritten: 3,
            entrySize: 1000, started: false, finished: false
        )
        #expect(throttle.feed(p1) != nil)
        // Same instant, different value → throttled by interval
        #expect(throttle.feed(p2) == nil)
        // Cross the interval → emits the next changed value
        now = Date(timeIntervalSinceReferenceDate: 100 + 1.0/24.0 + 0.001)
        #expect(throttle.feed(p3) != nil)
    }

    @Test("ProgressThrottle coalesces identical consecutive values (no-op suppression)")
    func throttle_identicalValues_coalesced() {
        var now = Date(timeIntervalSinceReferenceDate: 0)
        let throttle = ProgressThrottle(intervalHz: 24, now: { now })
        let p = Newtua.Progress(
            index: 0, path: "a", bytesWritten: 5,
            entrySize: 10, started: false, finished: false
        )
        #expect(throttle.feed(p) != nil)
        // Past the interval, but value unchanged → still nil (no-op suppress).
        now = Date(timeIntervalSinceReferenceDate: 10)
        #expect(throttle.feed(p) == nil)
    }

    @Test("ProgressThrottle always emits started and finished ticks")
    func throttle_startedFinished_alwaysEmit() {
        var now = Date(timeIntervalSinceReferenceDate: 0)
        let throttle = ProgressThrottle(intervalHz: 24, now: { now })
        let started = Newtua.Progress(
            index: 0, path: "a", bytesWritten: 0,
            entrySize: 10, started: true, finished: false
        )
        let mid = Newtua.Progress(
            index: 0, path: "a", bytesWritten: 5,
            entrySize: 10, started: false, finished: false
        )
        let finished = Newtua.Progress(
            index: 0, path: "a", bytesWritten: 10,
            entrySize: 10, started: false, finished: true
        )
        #expect(throttle.feed(started) != nil)
        now = Date(timeIntervalSinceReferenceDate: 0.001)
        #expect(throttle.feed(mid) == nil, "mid tick within interval must be throttled")
        now = Date(timeIntervalSinceReferenceDate: 0.002)
        #expect(throttle.feed(finished) != nil, "finished tick must always emit")
    }

    @Test("ProgressThrottle.flush returns the latest buffered tick exactly once")
    func throttle_flush_returnsBuffered() {
        var now = Date(timeIntervalSinceReferenceDate: 0)
        let throttle = ProgressThrottle(intervalHz: 24, now: { now })
        let first = Newtua.Progress(
            index: 0, path: "a", bytesWritten: 1,
            entrySize: 100, started: false, finished: false
        )
        let second = Newtua.Progress(
            index: 0, path: "a", bytesWritten: 2,
            entrySize: 100, started: false, finished: false
        )
        _ = throttle.feed(first)  // emits, lastEmit = 0
        now = Date(timeIntervalSinceReferenceDate: 0.001)
        #expect(throttle.feed(second) == nil)  // throttled, buffered
        let flushed = throttle.flush()
        #expect(flushed == second)
        #expect(throttle.flush() == nil)
    }

    @Test("ProgressThrottle emits the buffered snapshot value when interval re-opens")
    func throttle_emitsLatestSnapshot_afterInterval() {
        var now = Date(timeIntervalSinceReferenceDate: 0)
        let throttle = ProgressThrottle(intervalHz: 24, now: { now })
        let a = Newtua.Progress(
            index: 0, path: "a", bytesWritten: 1,
            entrySize: 100, started: false, finished: false
        )
        let b = Newtua.Progress(
            index: 0, path: "a", bytesWritten: 50,
            entrySize: 100, started: false, finished: false
        )
        _ = throttle.feed(a)
        now = Date(timeIntervalSinceReferenceDate: 0.001)
        #expect(throttle.feed(b) == nil)  // buffered
        // Past interval — next feed emits the most recent value (latest).
        now = Date(timeIntervalSinceReferenceDate: 1.0)
        let c = Newtua.Progress(
            index: 0, path: "a", bytesWritten: 75,
            entrySize: 100, started: false, finished: false
        )
        #expect(throttle.feed(c) == c)
    }
}
