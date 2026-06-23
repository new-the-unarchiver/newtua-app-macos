import Foundation
import Testing
import Newtua
@testable import NewTheUnarchiver

@MainActor
@Suite("Stage 4 — queue window (extended)")
struct Stage4ExtendedTests {

    // MARK: - QueueWindowVisibility — edges

    @Test("Visibility ignores empty pulses while already hidden")
    func visibility_emptyWhileHidden_staysHidden() {
        let v = QueueWindowVisibility(hideDelay: 0.3)
        let t0 = Date(timeIntervalSince1970: 0)
        let deadline1 = v.observe(isEmpty: true, at: t0)
        let deadline2 = v.observe(isEmpty: true, at: t0.addingTimeInterval(1))
        #expect(deadline1 == nil)
        #expect(deadline2 == nil)
        #expect(!v.shouldShow)
    }

    @Test("Second empty observation does not reset the pending hide deadline")
    func visibility_secondEmpty_doesNotReset() {
        let v = QueueWindowVisibility(hideDelay: 0.3)
        let t0 = Date(timeIntervalSince1970: 0)
        v.observe(isEmpty: false, at: t0)
        let first = v.observe(isEmpty: true, at: t0)
        let second = v.observe(isEmpty: true, at: t0.addingTimeInterval(0.1))
        #expect(first == second)
    }

    @Test("Tick before the deadline does not hide a pending-hide state")
    func visibility_tickBeforeDeadline_keepsShown() {
        let v = QueueWindowVisibility(hideDelay: 0.3)
        let t0 = Date(timeIntervalSince1970: 0)
        v.observe(isEmpty: false, at: t0)
        v.observe(isEmpty: true, at: t0)
        v.tick(at: t0.addingTimeInterval(0.299))
        #expect(v.shouldShow)
    }

    // MARK: - JobRowDisplay — edges

    @Test("JobRowDisplay shows no progress fraction when entry size is unknown")
    func display_running_unknownSize_noFraction() {
        let job = ArchiveJob(url: URL(fileURLWithPath: "/tmp/x.zip"))
        job.updateState(.running)
        job.recordProgress(TestSupport.tick(bytes: 100, of: 0, path: "a"))
        let d = JobRowDisplay(job: job)
        #expect(d.progressFraction == nil)
        #expect(d.subtitleKind == .running(currentPath: "a"))
    }

    @Test("JobRowDisplay carries the password-prompt reason from the job state")
    func display_needsPassword_preservesReason() {
        let job = ArchiveJob(url: URL(fileURLWithPath: "/tmp/locked.zip"))
        job.updateState(.running)
        job.updateState(.needsPassword(.wrongPassword))
        let d = JobRowDisplay(job: job)
        #expect(d.subtitleKind == .needsPassword(.wrongPassword))
        #expect(d.showsCancelButton)
    }

    @Test("JobRowDisplay surfaces the failure error code")
    func display_failed_carriesErrorCode() {
        let job = ArchiveJob(url: URL(fileURLWithPath: "/tmp/bad.zip"))
        job.updateState(.running)
        job.updateState(.failed(.corrupt))
        let d = JobRowDisplay(job: job)
        #expect(d.subtitleKind == .failed(.corrupt))
        #expect(!d.showsCancelButton)
    }

    @Test("JobRowDisplay title is the archive's last path component, not its full path")
    func display_title_isFilename() {
        let job = ArchiveJob(url: URL(fileURLWithPath: "/a/very/deep/path/archive.tar.gz"))
        #expect(JobRowDisplay(job: job).title == "archive.tar.gz")
    }

    // MARK: - ArchiveJob progress — additional edges

    @Test("ArchiveJob.recordProgress accepts equal bytes within the same entry (idempotent ticks)")
    func recordProgress_acceptsEqualBytes() {
        let job = ArchiveJob(url: URL(fileURLWithPath: "/tmp/a.zip"))
        job.updateState(.running)
        job.recordProgress(TestSupport.tick(bytes: 100, of: 200))
        job.recordProgress(TestSupport.tick(bytes: 100, of: 200, started: true))
        #expect(job.progress?.started == true)
    }

    // MARK: - AppModel — Stage 4 additions

    @Test("AppModel.enqueue drops directory URLs silently")
    func enqueue_ignoresDirectories() {
        let app = AppModel()
        let dir = URL(fileURLWithPath: "/tmp/some-folder", isDirectory: true)
        let file = URL(fileURLWithPath: "/tmp/some-folder/a.zip")
        app.enqueue(urls: [dir, file])
        #expect(app.queue.count == 1)
        #expect(app.queue.first?.url == file.standardizedFileURL)
    }

    @Test("AppModel.cancel drops a still-queued job and keeps a running one")
    func cancel_dropsQueued_keepsRunning() {
        let app = AppModel()
        app.enqueue(urls: [URL(fileURLWithPath: "/tmp/q.zip"), URL(fileURLWithPath: "/tmp/r.zip")])
        let queued = app.queue[0]
        let running = app.queue[1]
        running.updateState(.running)
        app.cancel(queued)
        app.cancel(running)
        #expect(app.queue.count == 1)
        #expect(app.queue.first?.id == running.id)
        #expect(running.state == .cancelled)
    }

    @Test("ArchiveJob.recordProgress ignores ticks once the job is no longer running")
    func recordProgress_ignoredAfterTerminal() {
        let job = ArchiveJob(url: URL(fileURLWithPath: "/tmp/a.zip"))
        job.updateState(.running)
        job.recordProgress(TestSupport.tick(bytes: 50, of: 200))
        job.updateState(.succeeded(ExtractReport(extracted: 1, failed: 0, aborted: false)))
        job.recordProgress(TestSupport.tick(bytes: 80, of: 200))
        #expect(job.progress?.bytesWritten == 50)
    }
}
