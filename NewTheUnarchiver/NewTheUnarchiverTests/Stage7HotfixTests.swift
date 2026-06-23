import Foundation
import Testing
@testable import NewTheUnarchiver

@MainActor
@Suite("Stage 7 — hotfix: cancel from .needsPassword / .needsEncoding must remove the row")
struct Stage7HotfixTests {

    @Test("Cancel from .needsPassword schedules removal via terminalDisplayDelay")
    func cancel_fromNeedsPassword_removesAfterDelay() async {
        let app = AppModel(terminalDisplayDelay: 0.05)
        app.enqueue(urls: [URL(fileURLWithPath: "/tmp/locked.zip")])
        let job = app.queue[0]
        job.updateState(.running)
        job.updateState(.needsPassword(.encrypted))

        app.cancel(job)

        #expect(job.state == .cancelled, "cancel() flips state immediately")
        #expect(app.queue.count == 1, "row stays visible during the display delay")
        try? await Task.sleep(for: .milliseconds(200))
        #expect(app.queue.isEmpty, "row must auto-drop after terminalDisplayDelay")
    }

    @Test("Cancel from .needsEncoding schedules removal via terminalDisplayDelay")
    func cancel_fromNeedsEncoding_removesAfterDelay() async {
        let app = AppModel(terminalDisplayDelay: 0.05)
        app.enqueue(urls: [URL(fileURLWithPath: "/tmp/cjk.zip")])
        let job = app.queue[0]
        job.updateState(.running)
        job.updateState(.needsEncoding(currentEncoding: nil))

        app.cancel(job)

        #expect(job.state == .cancelled)
        try? await Task.sleep(for: .milliseconds(200))
        #expect(app.queue.isEmpty)
    }

    @Test("Cancel from .running still relies on the scheduler's handleTerminal (no double-removal)")
    func cancel_fromRunning_remainsHandledByScheduler() async {
        // Even though `AppModel.cancel` will also fire `handleTerminal` now,
        // `remove(_:)` is idempotent — two scheduled removals must not
        // crash and must leave the queue empty exactly once.
        let app = AppModel(terminalDisplayDelay: 0.05)
        app.enqueue(urls: [URL(fileURLWithPath: "/tmp/running.zip")])
        let job = app.queue[0]
        job.updateState(.running)

        app.cancel(job)
        // Simulate what the scheduler's Task does after runner.run() unwinds:
        app.handleTerminal(job)

        try? await Task.sleep(for: .milliseconds(200))
        #expect(app.queue.isEmpty)
    }

    @Test("Cancel from .queued still removes synchronously (no regression)")
    func cancel_fromQueued_removesImmediately() {
        let app = AppModel(terminalDisplayDelay: 0.05)
        app.enqueue(urls: [URL(fileURLWithPath: "/tmp/q.zip")])
        let job = app.queue[0]
        app.cancel(job)
        #expect(app.queue.isEmpty)
    }
}
