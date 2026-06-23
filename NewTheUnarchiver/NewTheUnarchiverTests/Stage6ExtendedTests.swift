import Foundation
import Testing
import Newtua
@testable import NewTheUnarchiver

@MainActor
@Suite("Stage 6 — password & encoding prompts (extended)")
struct Stage6ExtendedTests {

    // MARK: - Password edges

    @Test("Empty password is accepted as a pending value (the engine decides validity)")
    func submitPassword_emptyString_isAccepted() {
        let app = AppModel()
        app.enqueue(urls: [URL(fileURLWithPath: "/tmp/a.zip")])
        let job = app.queue[0]
        job.updateState(.running)
        job.updateState(.needsPassword(.encrypted))

        let scheduler = Scheduler(model: app, probe: StubProbe(), maxParallel: 0)
        scheduler.submitPassword("", applyToAll: true, for: job)

        #expect(job.pendingPassword == "")
        #expect(app.sharedPassword == "")
    }

    @Test("Unicode password survives the round-trip verbatim")
    func submitPassword_unicodePassword_preserved() {
        let app = AppModel()
        app.enqueue(urls: [URL(fileURLWithPath: "/tmp/a.zip")])
        let job = app.queue[0]
        job.updateState(.running)
        job.updateState(.needsPassword(.encrypted))

        let scheduler = Scheduler(model: app, probe: StubProbe(), maxParallel: 0)
        let pw = "пароль-🔐-道路"
        scheduler.submitPassword(pw, applyToAll: false, for: job)

        #expect(job.pendingPassword == pw)
    }

    @Test("Whitespace in a password is preserved — we never trim user input")
    func submitPassword_whitespace_preservedAsIs() {
        let app = AppModel()
        app.enqueue(urls: [URL(fileURLWithPath: "/tmp/a.zip")])
        let job = app.queue[0]
        job.updateState(.running)
        job.updateState(.needsPassword(.encrypted))

        let scheduler = Scheduler(model: app, probe: StubProbe(), maxParallel: 0)
        scheduler.submitPassword("  spaced  ", applyToAll: false, for: job)

        #expect(job.pendingPassword == "  spaced  ")
    }

    @Test("A second password submission overwrites the previous pending value")
    func submitPassword_overwritesPrevious() {
        let app = AppModel()
        app.enqueue(urls: [URL(fileURLWithPath: "/tmp/a.zip")])
        let job = app.queue[0]
        job.updateState(.running)
        job.updateState(.needsPassword(.encrypted))

        let scheduler = Scheduler(model: app, probe: StubProbe(), maxParallel: 0)
        scheduler.submitPassword("first", applyToAll: false, for: job)
        job.updateState(.running)
        job.updateState(.needsPassword(.wrongPassword))
        scheduler.submitPassword("second", applyToAll: false, for: job)

        #expect(job.pendingPassword == "second")
    }

    // MARK: - Encoding edges

    @Test("Submitting nil encoding clears any prior override on the job")
    func submitEncoding_nilClearsOverride() {
        let app = AppModel()
        app.enqueue(urls: [URL(fileURLWithPath: "/tmp/a.zip")])
        let job = app.queue[0]
        job.updateState(.running)
        job.updateState(.needsEncoding(currentEncoding: "shift_jis"))

        let scheduler = Scheduler(model: app, probe: StubProbe(), maxParallel: 0)
        scheduler.submitEncoding("shift_jis", for: job)
        #expect(job.pendingEncoding == "shift_jis")
        job.updateState(.running)
        job.updateState(.needsEncoding(currentEncoding: "shift_jis"))
        scheduler.submitEncoding(nil, for: job)
        #expect(job.pendingEncoding == nil)
    }

    @Test("attachPendingEncoding replaces the value rather than appending")
    func attachPendingEncoding_replaces() {
        let job = ArchiveJob(url: URL(fileURLWithPath: "/tmp/a.zip"))
        job.attachPendingEncoding("cp866")
        job.attachPendingEncoding("shift_jis")
        #expect(job.pendingEncoding == "shift_jis")
    }

    // MARK: - Scheduler launch composition

    @Test("JobRunner carries the password and encoding it was given")
    func jobRunner_carriesPasswordAndEncoding() {
        let job = ArchiveJob(url: URL(fileURLWithPath: "/tmp/a.zip"))
        let runner = JobRunner(
            job: job,
            destination: URL(fileURLWithPath: "/tmp"),
            password: "pw",
            encoding: "cp866"
        )
        #expect(runner.password == "pw")
        #expect(runner.encoding == "cp866")
    }

    @Test("Scheduler.submitPassword leaves applyToAll == false untouched even after a previous Apply-to-All")
    func submitPassword_singleUseDoesNotClearShared() {
        let app = AppModel()
        app.enqueue(urls: [
            URL(fileURLWithPath: "/tmp/a.zip"),
            URL(fileURLWithPath: "/tmp/b.zip"),
        ])
        let scheduler = Scheduler(model: app, probe: StubProbe(), maxParallel: 0)

        let first = app.queue[0]
        first.updateState(.running)
        first.updateState(.needsPassword(.encrypted))
        scheduler.submitPassword("global", applyToAll: true, for: first)
        #expect(app.sharedPassword == "global")

        let second = app.queue[1]
        second.updateState(.running)
        second.updateState(.needsPassword(.encrypted))
        scheduler.submitPassword("local", applyToAll: false, for: second)
        #expect(app.sharedPassword == "global")
        #expect(second.pendingPassword == "local")
    }

    // MARK: - Debounce edges

    @Test("Debounce: an elapsed-equal-window submit runs immediately, not scheduled")
    func debounce_exactWindowBoundary_runsNow() {
        var d = EncodingPromptDebounce(window: 0.2)
        let t0 = Date(timeIntervalSince1970: 0)
        _ = d.submit("a", at: t0)
        d.recordResolved("a", at: t0)
        #expect(d.submit("b", at: t0.addingTimeInterval(0.2)) == .runNow)
    }

    @Test("Debounce: recordResolved moves the baseline forward")
    func debounce_recordResolved_movesBaseline() {
        var d = EncodingPromptDebounce(window: 0.2)
        let t0 = Date(timeIntervalSince1970: 0)
        _ = d.submit("a", at: t0)
        d.recordResolved("a", at: t0)
        d.recordResolved("b", at: t0.addingTimeInterval(0.5))
        // The new baseline is at t0+0.5; a quick follow-up to "c" at t0+0.6
        // (0.1s after baseline) must schedule, not runNow.
        let dec = d.submit("c", at: t0.addingTimeInterval(0.6))
        if case .scheduleAfter(let interval) = dec {
            #expect(abs(interval - 0.1) < 0.01)
        } else {
            Issue.record("Expected .scheduleAfter, got \(dec)")
        }
    }

    @Test("Debounce: nil encoding is a real value — repeating nil → skipNoChange")
    func debounce_nilEncodingTrackedAsValue() {
        var d = EncodingPromptDebounce(window: 0.2)
        let t0 = Date(timeIntervalSince1970: 0)
        _ = d.submit(nil, at: t0)
        d.recordResolved(nil, at: t0)
        #expect(d.submit(nil, at: t0.addingTimeInterval(0.05)) == .skipNoChange)
    }

    @Test("Debounce: switching to a different encoding after window runs immediately")
    func debounce_differentEncodingAfterWindow_runsNow() {
        var d = EncodingPromptDebounce(window: 0.2)
        let t0 = Date(timeIntervalSince1970: 0)
        _ = d.submit("a", at: t0)
        d.recordResolved("a", at: t0)
        #expect(d.submit("b", at: t0.addingTimeInterval(1.0)) == .runNow)
    }
}
