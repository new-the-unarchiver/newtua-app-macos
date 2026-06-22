import Foundation
import Testing
import Newtua
@testable import NewTheUnarchiver

@MainActor
@Suite("Stage 1 — extended (unit/edge)")
struct Stage1ExtendedTests {

    // MARK: - State transitions

    @Test("Terminal states block all outgoing transitions")
    func terminal_blocksTransitions() {
        let report = ExtractReport(extracted: 1, failed: 0, aborted: false)
        let terminals: [JobState] = [.succeeded(report), .failed(.io), .cancelled]
        let others: [JobState] = [.queued, .running, .needsPassword(.encrypted)]
        for t in terminals {
            for o in others {
                #expect(t.canTransition(to: o) == false, "\(t) → \(o) must be blocked")
            }
        }
    }

    @Test("Non-terminal states can transition to other states")
    func nonTerminal_canTransition() {
        let report = ExtractReport(extracted: 1, failed: 0, aborted: false)
        #expect(JobState.queued.canTransition(to: .running) == true)
        #expect(JobState.running.canTransition(to: .succeeded(report)) == true)
        #expect(JobState.needsPassword(.encrypted).canTransition(to: .running) == true)
        #expect(JobState.needsEncoding(currentEncoding: nil).canTransition(to: .running) == true)
    }

    @Test("isTerminal classifies states correctly")
    func isTerminal_classification() {
        #expect(JobState.queued.isTerminal == false)
        #expect(JobState.running.isTerminal == false)
        #expect(JobState.needsPassword(.encrypted).isTerminal == false)
        #expect(JobState.needsEncoding(currentEncoding: nil).isTerminal == false)
        #expect(JobState.succeeded(ExtractReport(extracted: 0, failed: 0, aborted: false)).isTerminal == true)
        #expect(JobState.failed(.io).isTerminal == true)
        #expect(JobState.cancelled.isTerminal == true)
    }

    // MARK: - Equatable

    @Test("JobState equality covers payload variations")
    func jobState_equatable() {
        let r1 = ExtractReport(extracted: 1, failed: 0, aborted: false)
        let r2 = ExtractReport(extracted: 1, failed: 0, aborted: false)
        let r3 = ExtractReport(extracted: 2, failed: 0, aborted: false)
        #expect(JobState.queued == JobState.queued)
        #expect(JobState.running != JobState.queued)
        #expect(JobState.succeeded(r1) == JobState.succeeded(r2))
        #expect(JobState.succeeded(r1) != JobState.succeeded(r3))
        #expect(JobState.failed(.io) == JobState.failed(.io))
        #expect(JobState.failed(.io) != JobState.failed(.corrupt))
        #expect(JobState.needsPassword(.encrypted) != JobState.needsPassword(.wrongPassword))
        #expect(JobState.needsEncoding(currentEncoding: "cp866") == JobState.needsEncoding(currentEncoding: "cp866"))
    }

    // MARK: - Empty / bulk

    @Test("AppModel starts with an empty queue and no shared password")
    func appModel_defaultEmpty() {
        let app = AppModel()
        #expect(app.queue.isEmpty)
        #expect(app.sharedPassword == nil)
    }

    @Test("Enqueueing 50 unique URLs grows queue to 50")
    func enqueue_50uniqueUrls() {
        let app = AppModel()
        let urls = (0..<50).map { URL(fileURLWithPath: "/tmp/a\($0).zip") }
        app.enqueue(urls: urls)
        #expect(app.queue.count == 50)
    }

    @Test("remove(_:) takes a job out of the queue")
    func remove_takesJobOut() {
        let app = AppModel()
        app.enqueue(urls: [URL(fileURLWithPath: "/tmp/a.zip")])
        let job = app.queue[0]
        app.remove(job)
        #expect(app.queue.isEmpty)
    }

    // MARK: - Dedup behaviour

    @Test("Dedup uses standardizedFileURL so '..' segments resolve and collide")
    func dedup_standardizedFileURL() {
        let app = AppModel()
        app.enqueue(urls: [
            URL(fileURLWithPath: "/tmp/foo/../a.zip"),
            URL(fileURLWithPath: "/tmp/a.zip"),
        ])
        #expect(app.queue.count == 1)
    }

    @Test("Dedup only blocks against non-terminal jobs; finished jobs allow re-adding")
    func dedup_onlyAgainstActive() {
        let app = AppModel()
        let url = URL(fileURLWithPath: "/tmp/a.zip")
        app.enqueue(urls: [url])
        let job = app.queue[0]
        job.updateState(.succeeded(ExtractReport(extracted: 1, failed: 0, aborted: false)))
        app.enqueue(urls: [url])
        #expect(app.queue.count == 2)
    }

    // MARK: - Cancellation invariants

    @Test("Cancel on a terminal state is a no-op")
    func cancel_onTerminal_noop() {
        let app = AppModel()
        app.enqueue(urls: [URL(fileURLWithPath: "/tmp/a.zip")])
        let job = app.queue[0]
        let report = ExtractReport(extracted: 1, failed: 0, aborted: false)
        job.updateState(.succeeded(report))
        job.cancel()
        #expect(job.state == .succeeded(report))
    }

    @Test("Cancel flips the cancellation token regardless of state")
    func cancel_flipsToken() {
        let app = AppModel()
        app.enqueue(urls: [URL(fileURLWithPath: "/tmp/a.zip")])
        let job = app.queue[0]
        #expect(job.cancellation.isCancelled == false)
        job.cancel()
        #expect(job.cancellation.isCancelled == true)
    }

    // MARK: - Shared password

    @Test("clearSharedPassword() resets to nil")
    func clearSharedPassword_resets() {
        let app = AppModel()
        app.setSharedPassword("pw", applyToAll: true)
        #expect(app.sharedPassword == "pw")
        app.clearSharedPassword()
        #expect(app.sharedPassword == nil)
    }

    // MARK: - ExtractionOptions defaults

    @Test("ExtractionOptions defaults match the original Unarchiver")
    func extractionOptions_defaultsMatchOriginal() {
        let opts = ExtractionOptions()
        #expect(opts.wrapperMode == .onlyIfMultiple)
        #expect(opts.destinationStrategy == .nextToArchive)
        #expect(opts.openFolderAfter == false)
        #expect(opts.moveToTrashAfter == false)
    }

}
