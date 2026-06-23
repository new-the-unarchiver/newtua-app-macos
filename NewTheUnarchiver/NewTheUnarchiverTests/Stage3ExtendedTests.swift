import Foundation
import Testing
import Newtua
@testable import NewTheUnarchiver

@MainActor
@Suite("Stage 3 — extended (scheduler / probe / integration)")
struct Stage3ExtendedTests {

    // MARK: - SystemVolumeProbe (integration)

    @Test("SystemVolumeProbe says the root volume is internal on a Mac")
    func systemProbe_rootIsInternal() {
        let probe = SystemVolumeProbe()
        #expect(probe.isInternal(URL(fileURLWithPath: "/")))
    }

    @Test("SystemVolumeProbe classifies the root volume as .ssd on modern macOS")
    func systemProbe_rootMediumIsSSD() {
        // v1 heuristic: internal → .ssd. On Apple Silicon and macOS 26+ this
        // is true for the system volume.
        #expect(SystemVolumeProbe().mediumType(URL(fileURLWithPath: "/")) == .ssd)
    }

    @Test("SystemVolumeProbe returns .unknown for a non-existent URL")
    func systemProbe_missingURL_unknown() {
        let probe = SystemVolumeProbe()
        let bogus = URL(fileURLWithPath: "/var/empty/no-such-volume-\(UUID().uuidString)/x")
        #expect(probe.isInternal(bogus) == false)
        #expect(probe.mediumType(bogus) == .unknown)
    }

    // MARK: - Predicate edges

    @Test("Predicate is unaffected by terminal states on the other side")
    func predicate_terminalStateDoesNotBlock() {
        let aJob = ArchiveJob(url: URL(fileURLWithPath: "/tmp/a.zip"))
        aJob.updateState(.running)
        aJob.updateState(.succeeded(ExtractReport(extracted: 1, failed: 0, aborted: false)))
        let a = PendingJob(job: aJob, destination: URL(fileURLWithPath: "/tmp/oa"))
        let b = PendingJob(
            job: ArchiveJob(url: URL(fileURLWithPath: "/tmp/b.zip")),
            destination: URL(fileURLWithPath: "/tmp/ob")
        )
        #expect(areCompatible(a, b, probe: StubProbe()))
    }

    // MARK: - Scheduler — pick / cap

    @Test("Scheduler returns nil when the only active is awaiting password input")
    func scheduler_pickCompatible_noneAvailable() {
        let app = AppModel()
        app.enqueue(urls: [
            URL(fileURLWithPath: "/tmp/a/x.zip"),
            URL(fileURLWithPath: "/tmp/b/y.zip"),
        ])
        let s = Scheduler(model: app, probe: StubProbe(), maxParallel: 4)
        let a = app.queue[0]
        a.updateState(.running)
        a.updateState(.needsPassword(.encrypted))
        s.markActive(a, destination: a.defaultDestination)
        #expect(s.pickCompatibleQueuedJob() == nil)
    }

    @Test("Scheduler falls back to maxParallel=1 when CPU reports a single core")
    func scheduler_singleCpu_fallsBackToSerial() {
        let app = AppModel()
        #expect(Scheduler(model: app, probe: StubProbe(), cpuCount: { 1 }).maxParallel == 1)
    }

    @Test("Scheduler caps maxParallel at a positive integer even if cpuCount returns 0")
    func scheduler_zeroCpu_clampsToOne() {
        // Safety: ProcessInfo can lie or a mock might return 0. Never run zero.
        let app = AppModel()
        #expect(Scheduler(model: app, probe: StubProbe(), cpuCount: { 0 }).maxParallel == 1)
    }

    // MARK: - Scheduler — integration (drain via real runners)

    @Test("Scheduler.dispatch on an empty queue is a no-op")
    func scheduler_emptyQueue_noop() async {
        let app = AppModel()
        let s = Scheduler(model: app, probe: StubProbe())
        s.dispatch()
        await s.waitUntilQuiescent()
        #expect(app.queue.isEmpty)
    }

    @Test("Scheduler drains all queued jobs to .succeeded via real extraction")
    func scheduler_drainsAllJobs_toSucceeded() async throws {
        let tmp = try TestSupport.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        // Copy fixtures into different sub-dirs so destinations don't collide
        // (defaultDestination = next to archive).
        let dirA = tmp.appendingPathComponent("a", isDirectory: true)
        let dirB = tmp.appendingPathComponent("b", isDirectory: true)
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)
        let h7z = dirA.appendingPathComponent("hello.7z")
        let hrar = dirB.appendingPathComponent("hello.rar")
        try FileManager.default.copyItem(at: TestSupport.fixture("hello.7z"), to: h7z)
        try FileManager.default.copyItem(at: TestSupport.fixture("hello.rar"), to: hrar)

        let app = AppModel()
        app.enqueue(urls: [h7z, hrar])
        let s = Scheduler(model: app, probe: StubProbe(), maxParallel: 2)
        s.dispatch()
        await s.waitUntilQuiescent()

        for job in app.queue {
            if case .succeeded = job.state { continue }
            Issue.record("Job \(job.url.lastPathComponent) not .succeeded: \(job.state)")
        }
    }

    @Test("Scheduler does not relaunch jobs already in a terminal state")
    func scheduler_skipsTerminalJobs() async throws {
        let app = AppModel()
        app.enqueue(urls: [TestSupport.fixture("hello.7z")])
        let pre = try #require(app.queue.first)
        pre.cancel()
        #expect(pre.state == .cancelled)

        let s = Scheduler(model: app, probe: StubProbe())
        s.dispatch()
        await s.waitUntilQuiescent()
        #expect(pre.state == .cancelled)
    }

    @Test("Scheduler.dispatch never exceeds maxParallel active jobs")
    func scheduler_doesNotExceedMaxParallel() {
        let app = AppModel()
        // Five queued jobs in separate directories so destinations don't clash.
        let urls = (0..<5).map { URL(fileURLWithPath: "/tmp/parallel-\($0)/a.zip") }
        app.enqueue(urls: urls)
        let s = Scheduler(model: app, probe: StubProbe(), maxParallel: 2)

        // Two pretend-active jobs occupy both slots.
        s.markActive(app.queue[0], destination: URL(fileURLWithPath: "/tmp/d0"))
        s.markActive(app.queue[1], destination: URL(fileURLWithPath: "/tmp/d1"))
        #expect(s.activeCount == 2)

        s.dispatch()
        // Both slots are full → dispatch must not launch a third.
        #expect(s.activeCount == 2)
    }
}
