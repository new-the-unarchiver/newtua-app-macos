import Foundation
import Testing
import Newtua
@testable import NewTheUnarchiver

@MainActor
@Suite("Stage 6 — password & encoding prompts (TDD minimum)")
struct Stage6Tests {

    // MARK: - Password flow

    @Test("Submitting a password with Apply-to-All stores it on AppModel and requeues the job")
    func submitPassword_applyToAll_setsSharedAndRequeues() {
        let app = AppModel()
        app.enqueue(urls: [
            URL(fileURLWithPath: "/tmp/a.zip"),
            URL(fileURLWithPath: "/tmp/b.zip"),
        ])
        let job = app.queue[0]
        job.updateState(.running)
        job.updateState(.needsPassword(.encrypted))

        // maxParallel: 0 prevents the dispatch loop from launching anything
        // real; tests verify the state machine only.
        let scheduler = Scheduler(model: app, probe: StubProbe(), maxParallel: 0)
        scheduler.submitPassword("secret", applyToAll: true, for: job)

        #expect(app.sharedPassword == "secret")
        #expect(job.pendingPassword == "secret")
        #expect(job.state == .queued)
    }

    @Test("Single-use password attaches to the job but does NOT touch AppModel.sharedPassword")
    func submitPassword_singleUse_attachesPendingOnly() {
        let app = AppModel()
        app.enqueue(urls: [URL(fileURLWithPath: "/tmp/a.zip")])
        let job = app.queue[0]
        job.updateState(.running)
        job.updateState(.needsPassword(.encrypted))

        let scheduler = Scheduler(model: app, probe: StubProbe(), maxParallel: 0)
        scheduler.submitPassword("secret", applyToAll: false, for: job)

        #expect(app.sharedPassword == nil)
        #expect(job.pendingPassword == "secret")
        #expect(job.state == .queued)
    }

    // MARK: - Encoding flow

    @Test("Submitting a chosen encoding attaches it to the job and requeues it")
    func submitEncoding_movesJobToQueued_withChosenEncoding() {
        let app = AppModel()
        app.enqueue(urls: [URL(fileURLWithPath: "/tmp/cjk.zip")])
        let job = app.queue[0]
        job.updateState(.running)
        job.updateState(.needsEncoding(currentEncoding: nil))

        let scheduler = Scheduler(model: app, probe: StubProbe(), maxParallel: 0)
        scheduler.submitEncoding("shift_jis", for: job)

        #expect(job.pendingEncoding == "shift_jis")
        #expect(job.state == .queued)
    }

    // MARK: - Encoding preview debounce (pure state machine)

    @Test("EncodingPromptDebounce: first submit runs immediately; repeating the same value is a no-op; quick change schedules")
    func encodingDebounce_pureContract() {
        var d = EncodingPromptDebounce(window: 0.2)
        let t0 = Date(timeIntervalSince1970: 0)

        // First submit always runs — no last-resolved baseline yet.
        #expect(d.submit("shift_jis", at: t0) == .runNow)
        d.recordResolved("shift_jis", at: t0)

        // Same value again → skip.
        #expect(d.submit("shift_jis", at: t0.addingTimeInterval(0.05)) == .skipNoChange)

        // Different value within the debounce window → schedule, don't run yet.
        let next = t0.addingTimeInterval(0.10)
        if case .scheduleAfter(let interval) = d.submit("cp866", at: next) {
            // Window is 0.2s, last-resolved was at t0, so 0.10 remains.
            #expect(abs(interval - 0.10) < 0.01)
        } else {
            Issue.record("Expected .scheduleAfter at the 100ms mark; got \(d.submit("cp866", at: next))")
        }

        // After the window elapses, the same value runs immediately.
        #expect(d.submit("cp866", at: t0.addingTimeInterval(0.25)) == .runNow)
    }
}
