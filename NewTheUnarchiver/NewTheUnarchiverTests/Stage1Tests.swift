import Foundation
import Testing
import Newtua
@testable import NewTheUnarchiver

@MainActor
@Suite("Stage 1 — Domain model (TDD-min)")
struct Stage1Tests {

    @Test("enqueue adds a job and deduplicates by standardized URL")
    func enqueue_addsJob_andDeduplicates() {
        let app = AppModel()
        let url = URL(fileURLWithPath: "/tmp/sample.zip")
        app.enqueue(urls: [url])
        app.enqueue(urls: [url])
        #expect(app.queue.count == 1)
    }

    @Test("from .succeeded the state cannot transition to .queued")
    func jobState_transitionsAreValid() {
        let report = ExtractReport(extracted: 1, failed: 0, aborted: false)
        let succeeded = JobState.succeeded(report)
        #expect(succeeded.canTransition(to: .queued) == false)
    }

    @Test("cancelling a running job sets state to .cancelled but keeps the row")
    func cancelRunning_marksAsCancelled_keepsRowUntilFinish() {
        let app = AppModel()
        let url = URL(fileURLWithPath: "/tmp/sample.zip")
        app.enqueue(urls: [url])
        let job = app.queue[0]
        job.updateState(.running)
        job.cancel()
        #expect(job.state == .cancelled)
        #expect(app.queue.contains(where: { $0.id == job.id }))
    }

    @Test("sharedPassword is set only when applyToAll is true")
    func sharedPassword_isOnlySetWhenApplyToAllChecked() {
        let app = AppModel()
        app.setSharedPassword("pw", applyToAll: false)
        #expect(app.sharedPassword == nil)
        app.setSharedPassword("pw", applyToAll: true)
        #expect(app.sharedPassword == "pw")
    }
}
