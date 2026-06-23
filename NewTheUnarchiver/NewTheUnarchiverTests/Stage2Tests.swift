import Foundation
import Testing
import Newtua
@testable import NewTheUnarchiver

@MainActor
@Suite("Stage 2 — engine queue (TDD minimum)")
struct Stage2Tests {

    @Test("Runner extracts a simple archive and marks the job succeeded")
    func runner_completes_simpleArchive() async throws {
        let app = AppModel()
        app.enqueue(urls: [TestSupport.fixture("hello.7z")])
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
        #expect(report.failed == 0)
        #expect(report.aborted == false)
        // hello.7z has a single top-level entry → `.onlyIfMultiple`
        // (default) leaves it flat at `<dest>/a.txt`.
        let written = dest.appendingPathComponent("a.txt")
        #expect(FileManager.default.fileExists(atPath: written.path))
    }

    @Test("Runner reports needsPassword on an encrypted archive without a password")
    func runner_reportsNeedsPassword_onEncrypted() async throws {
        let app = AppModel()
        app.enqueue(urls: [TestSupport.fixture("secret.7z")])
        let job = try #require(app.queue.first)

        let dest = try TestSupport.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dest) }

        let runner = JobRunner(job: job, destination: dest)
        await runner.run()

        #expect(job.state == .needsPassword(.encrypted))
    }

    @Test("Runner sets job state to .cancelled when cancellation token is tripped")
    func runner_cancellation_setsCancelled() async throws {
        let app = AppModel()
        app.enqueue(urls: [TestSupport.fixture("hello.7z")])
        let job = try #require(app.queue.first)

        let dest = try TestSupport.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dest) }

        job.cancel()  // pre-cancel
        let runner = JobRunner(job: job, destination: dest)
        await runner.run()

        #expect(job.state == .cancelled)
    }

    @Test("ProgressThrottle emits at most 24Hz under a 1000-tick/sec burst")
    func throttle_emitsAtMost24Hz_underBurst() {
        var fakeNow = Date(timeIntervalSinceReferenceDate: 0)
        let throttle = ProgressThrottle(intervalHz: 24, now: { fakeNow })

        var emits = 0
        for i in 0..<1000 {
            // 1ms steps → 1000 ticks across 1 second
            fakeNow = Date(timeIntervalSinceReferenceDate: Double(i) / 1000.0)
            if throttle.feed(TestSupport.tick(bytes: UInt64(i))) != nil { emits += 1 }
        }
        #expect(emits <= 25, "Got \(emits) emits, expected ≤ 25 under a 24Hz cap")
    }
}
