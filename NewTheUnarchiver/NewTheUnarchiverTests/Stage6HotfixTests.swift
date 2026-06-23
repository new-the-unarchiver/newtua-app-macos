import Foundation
import Testing
import Newtua
@testable import NewTheUnarchiver

@MainActor
@Suite("Stage 6 — hotfix: apply-to-all fan-out + shared-password distinction")
struct Stage6HotfixTests {

    // MARK: - Apply-to-All fan-out

    @Test("Apply-to-All requeues every other job currently awaiting a password with the same value")
    func applyToAll_requeuesAllPending() {
        let app = AppModel()
        app.enqueue(urls: [
            URL(fileURLWithPath: "/tmp/a.zip"),
            URL(fileURLWithPath: "/tmp/b.zip"),
            URL(fileURLWithPath: "/tmp/c.zip"),
        ])
        // All three race into needsPassword in parallel before the user types.
        for job in app.queue {
            job.updateState(.running)
            job.updateState(.needsPassword(.encrypted))
        }

        let scheduler = Scheduler(model: app, probe: StubProbe(), maxParallel: 0)
        let first = app.queue[0]
        scheduler.submitPassword("pw", applyToAll: true, for: first)

        #expect(app.sharedPassword == "pw")
        for job in app.queue {
            #expect(job.pendingPassword == "pw", "every awaiting job should get the shared password attached")
            #expect(job.state == .queued, "every awaiting job should be reset to .queued")
        }
    }

    @Test("Apply-to-All ignores jobs that are running or terminal")
    func applyToAll_skipsRunningAndTerminal() {
        let app = AppModel()
        app.enqueue(urls: [
            URL(fileURLWithPath: "/tmp/a.zip"),
            URL(fileURLWithPath: "/tmp/b.zip"),
            URL(fileURLWithPath: "/tmp/c.zip"),
            URL(fileURLWithPath: "/tmp/d.zip"),
        ])
        let waiting = app.queue[0]
        waiting.updateState(.running)
        waiting.updateState(.needsPassword(.encrypted))
        let running = app.queue[1]
        running.updateState(.running)
        let done = app.queue[2]
        done.updateState(.running)
        done.updateState(.succeeded(ExtractReport(extracted: 1, failed: 0, aborted: false)))
        let alsoWaiting = app.queue[3]
        alsoWaiting.updateState(.running)
        alsoWaiting.updateState(.needsPassword(.encrypted))

        let scheduler = Scheduler(model: app, probe: StubProbe(), maxParallel: 0)
        scheduler.submitPassword("pw", applyToAll: true, for: waiting)

        // Both waiting jobs requeued
        #expect(waiting.state == .queued)
        #expect(waiting.pendingPassword == "pw")
        #expect(alsoWaiting.state == .queued)
        #expect(alsoWaiting.pendingPassword == "pw")
        // Running and terminal jobs left alone
        #expect(running.state == .running)
        #expect(running.pendingPassword == nil)
        #expect(done.state == .succeeded(ExtractReport(extracted: 1, failed: 0, aborted: false)))
        #expect(done.pendingPassword == nil)
    }

    // MARK: - Shared vs explicit wrong password

    @Test("JobRunner: a wrong SHARED password ends in .sharedDidNotMatch, not .wrongPassword")
    func runner_sharedWrongPassword_setsSharedDidNotMatch() async throws {
        let app = AppModel()
        app.enqueue(urls: [TestSupport.fixture("secret.zip")])
        let job = try #require(app.queue.first)
        let dest = try TestSupport.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dest) }

        let runner = JobRunner(
            job: job,
            destination: dest,
            password: "definitely-wrong",
            passwordIsShared: true
        )
        await runner.run()

        #expect(job.state == .needsPassword(.sharedDidNotMatch))
    }

    @Test("JobRunner: a wrong EXPLICIT password still ends in .wrongPassword")
    func runner_explicitWrongPassword_setsWrongPassword() async throws {
        let app = AppModel()
        app.enqueue(urls: [TestSupport.fixture("secret.zip")])
        let job = try #require(app.queue.first)
        let dest = try TestSupport.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dest) }

        // passwordIsShared defaults to false — caller typed the password.
        let runner = JobRunner(
            job: job,
            destination: dest,
            password: "definitely-wrong"
        )
        await runner.run()

        #expect(job.state == .needsPassword(.wrongPassword))
    }

    // MARK: - Extended edges

    @Test("Apply-to-All overwrites a previously-remembered shared password")
    func applyToAll_overwritesSharedPassword() {
        let app = AppModel()
        app.setSharedPassword("old", applyToAll: true)
        app.enqueue(urls: [URL(fileURLWithPath: "/tmp/x.zip")])
        let job = app.queue[0]
        job.updateState(.running)
        job.updateState(.needsPassword(.encrypted))

        let scheduler = Scheduler(model: app, probe: StubProbe(), maxParallel: 0)
        scheduler.submitPassword("new", applyToAll: true, for: job)

        #expect(app.sharedPassword == "new")
    }

    @Test("Apply-to-All requeues a job already in .sharedDidNotMatch, not just .encrypted")
    func applyToAll_requeuesSharedDidNotMatchJobs() {
        let app = AppModel()
        app.enqueue(urls: [
            URL(fileURLWithPath: "/tmp/a.zip"),
            URL(fileURLWithPath: "/tmp/b.zip"),
        ])
        let first = app.queue[0]
        first.updateState(.running)
        first.updateState(.needsPassword(.encrypted))
        let second = app.queue[1]
        second.updateState(.running)
        second.updateState(.needsPassword(.sharedDidNotMatch))

        let scheduler = Scheduler(model: app, probe: StubProbe(), maxParallel: 0)
        scheduler.submitPassword("pw", applyToAll: true, for: first)

        #expect(second.state == .queued)
        #expect(second.pendingPassword == "pw")
    }

    @Test("Single-use password does not fan out to other awaiting jobs")
    func singleUsePassword_doesNotFanOut() {
        let app = AppModel()
        app.enqueue(urls: [
            URL(fileURLWithPath: "/tmp/a.zip"),
            URL(fileURLWithPath: "/tmp/b.zip"),
        ])
        for job in app.queue {
            job.updateState(.running)
            job.updateState(.needsPassword(.encrypted))
        }

        let scheduler = Scheduler(model: app, probe: StubProbe(), maxParallel: 0)
        scheduler.submitPassword("pw", applyToAll: false, for: app.queue[0])

        #expect(app.queue[0].pendingPassword == "pw")
        #expect(app.queue[0].state == .queued)
        #expect(app.queue[1].pendingPassword == nil)
        #expect(app.queue[1].state == .needsPassword(.encrypted))
        // Single-use must never persist on the model — otherwise the next
        // dropped archive would silently reuse it.
        #expect(app.sharedPassword == nil)
    }

    @Test("JobRowDisplay surfaces the .sharedDidNotMatch reason for the row subtitle")
    func display_sharedDidNotMatch_isPreserved() {
        let job = ArchiveJob(url: URL(fileURLWithPath: "/tmp/x.zip"))
        job.updateState(.running)
        job.updateState(.needsPassword(.sharedDidNotMatch))
        let d = JobRowDisplay(job: job)
        #expect(d.subtitleKind == .needsPassword(.sharedDidNotMatch))
        #expect(d.showsCancelButton)
    }

    @Test("JobRunner: a wrong shared password leaves the destination empty")
    func runner_sharedWrongPassword_writesNothing() async throws {
        let app = AppModel()
        app.enqueue(urls: [TestSupport.fixture("secret.zip")])
        let job = try #require(app.queue.first)
        let dest = try TestSupport.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dest) }

        let runner = JobRunner(
            job: job,
            destination: dest,
            password: "definitely-wrong",
            passwordIsShared: true
        )
        await runner.run()

        let written = (try? FileManager.default.contentsOfDirectory(atPath: dest.path)) ?? []
        #expect(written.isEmpty, "engine contract: nothing on disk after auth failure")
    }
}
