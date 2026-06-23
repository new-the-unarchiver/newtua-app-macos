import Foundation
import Testing
import Newtua
@testable import NewTheUnarchiver

@MainActor
@Suite("Stage 4 — queue window (TDD minimum)")
struct Stage4Tests {

    // MARK: - QueueWindowVisibility

    @Test("Visibility starts hidden and shows immediately when the queue becomes non-empty")
    func visibility_emptyStartsHidden_andShowsOnFirstJob() {
        let v = QueueWindowVisibility(hideDelay: 0.3)
        #expect(!v.shouldShow)
        v.observe(isEmpty: false, at: Date(timeIntervalSince1970: 0))
        #expect(v.shouldShow)
    }

    @Test("Visibility hides only after the debounce deadline elapses")
    func visibility_pendingHide_respectsDeadline() {
        let v = QueueWindowVisibility(hideDelay: 0.3)
        let t0 = Date(timeIntervalSince1970: 0)
        v.observe(isEmpty: false, at: t0)
        let deadline = v.observe(isEmpty: true, at: t0)
        #expect(v.shouldShow)
        #expect(deadline == t0.addingTimeInterval(0.3))
        v.tick(at: t0.addingTimeInterval(0.1))
        #expect(v.shouldShow)
        v.tick(at: t0.addingTimeInterval(0.3))
        #expect(!v.shouldShow)
    }

    @Test("Visibility cancels a pending hide when the queue refills before the deadline")
    func visibility_quickRefill_cancelsHide() {
        let v = QueueWindowVisibility(hideDelay: 0.3)
        let t0 = Date(timeIntervalSince1970: 0)
        v.observe(isEmpty: false, at: t0)
        v.observe(isEmpty: true, at: t0)
        v.observe(isEmpty: false, at: t0.addingTimeInterval(0.05))
        v.tick(at: t0.addingTimeInterval(0.5))
        #expect(v.shouldShow)
    }

    // MARK: - JobRowDisplay

    @Test("JobRowDisplay maps a queued job to the queued subtitle and no progress")
    func display_queued() {
        let job = ArchiveJob(url: URL(fileURLWithPath: "/tmp/archive.zip"))
        let d = JobRowDisplay(job: job)
        #expect(d.title == "archive.zip")
        #expect(d.subtitleKind == .queued)
        #expect(d.progressFraction == nil)
        #expect(d.showsCancelButton)
    }

    @Test("JobRowDisplay surfaces the running entry path and a deterministic progress fraction")
    func display_running_withProgress() {
        let job = ArchiveJob(url: URL(fileURLWithPath: "/tmp/big.7z"))
        job.updateState(.running)
        job.recordProgress(TestSupport.tick(bytes: 50, of: 200, path: "file.txt"))
        let d = JobRowDisplay(job: job)
        #expect(d.subtitleKind == .running(currentPath: "file.txt"))
        #expect(d.progressFraction == 0.25)
        #expect(d.showsCancelButton)
    }

    @Test("JobRowDisplay hides the cancel button once the job reaches a terminal state")
    func display_terminal_noCancel() {
        let job = ArchiveJob(url: URL(fileURLWithPath: "/tmp/done.zip"))
        job.updateState(.running)
        job.updateState(.succeeded(ExtractReport(extracted: 1, failed: 0, aborted: false)))
        #expect(!JobRowDisplay(job: job).showsCancelButton)
    }

    // MARK: - ArchiveJob progress monotonicity (guard added in Stage 4)

    @Test("ArchiveJob.recordProgress ignores backward bytes within the same entry")
    func recordProgress_ignoresBackwardBytes() {
        let job = ArchiveJob(url: URL(fileURLWithPath: "/tmp/a.zip"))
        job.updateState(.running)
        job.recordProgress(TestSupport.tick(bytes: 100, of: 200))
        job.recordProgress(TestSupport.tick(bytes: 50, of: 200))
        #expect(job.progress?.bytesWritten == 100)
    }

    @Test("ArchiveJob.recordProgress accepts a transition to the next entry")
    func recordProgress_acceptsNextEntry() {
        let job = ArchiveJob(url: URL(fileURLWithPath: "/tmp/a.zip"))
        job.updateState(.running)
        job.recordProgress(TestSupport.tick(bytes: 100, of: 200, index: 0, path: "a"))
        job.recordProgress(TestSupport.tick(bytes: 0, of: 50, index: 1, path: "b", started: true))
        #expect(job.progress?.index == 1)
        #expect(job.progress?.path == "b")
    }
}
