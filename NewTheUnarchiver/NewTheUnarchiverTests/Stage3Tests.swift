import Foundation
import Testing
import Newtua
@testable import NewTheUnarchiver

/// Test double for `VolumeProbing` — no-system-calls, per-URL overrides.
/// Shared with `Stage3ExtendedTests.swift` via the test target's internal scope.
struct StubProbe: VolumeProbing {
    var defaultInternal: Bool = true
    var defaultMedium: VolumeMediumType = .ssd
    var overrides: [URL: (isInternal: Bool, medium: VolumeMediumType)] = [:]

    func isInternal(_ url: URL) -> Bool {
        overrides[url.standardizedFileURL]?.isInternal ?? defaultInternal
    }
    func mediumType(_ url: URL) -> VolumeMediumType {
        overrides[url.standardizedFileURL]?.medium ?? defaultMedium
    }
}

@MainActor
@Suite("Stage 3 — scheduler (TDD minimum)")
struct Stage3Tests {

    // MARK: - CompatibilityPredicate

    @Test("Predicate blocks parallel if either job is on an external or HDD volume")
    func predicate_blocksParallel_ifEitherIsExternalOrHDD() {
        let a = PendingJob(
            job: ArchiveJob(url: URL(fileURLWithPath: "/tmp/a.zip")),
            destination: URL(fileURLWithPath: "/tmp/out-a")
        )
        let b = PendingJob(
            job: ArchiveJob(url: URL(fileURLWithPath: "/tmp/b.zip")),
            destination: URL(fileURLWithPath: "/tmp/out-b")
        )

        let externalA = StubProbe(overrides: [a.job.url: (isInternal: false, medium: .ssd)])
        #expect(!areCompatible(a, b, probe: externalA))

        let hddB = StubProbe(overrides: [b.job.url: (isInternal: true, medium: .hdd)])
        #expect(!areCompatible(a, b, probe: hddB))

        let unknownB = StubProbe(overrides: [b.job.url: (isInternal: true, medium: .unknown)])
        #expect(!areCompatible(a, b, probe: unknownB))
    }

    @Test("Predicate blocks parallel if jobs share the same destination folder")
    func predicate_blocksParallel_ifSameDestination() {
        let dest = URL(fileURLWithPath: "/tmp/out")
        let a = PendingJob(job: ArchiveJob(url: URL(fileURLWithPath: "/tmp/a.zip")), destination: dest)
        let b = PendingJob(job: ArchiveJob(url: URL(fileURLWithPath: "/tmp/b.zip")), destination: dest)
        #expect(!areCompatible(a, b, probe: StubProbe()))
    }

    @Test("Predicate blocks parallel if either job is awaiting password input")
    func predicate_blocksParallel_ifEitherEncrypted() {
        let aJob = ArchiveJob(url: URL(fileURLWithPath: "/tmp/a.zip"))
        aJob.updateState(.running)
        aJob.updateState(.needsPassword(.encrypted))
        let a = PendingJob(job: aJob, destination: URL(fileURLWithPath: "/tmp/oa"))
        let b = PendingJob(
            job: ArchiveJob(url: URL(fileURLWithPath: "/tmp/b.zip")),
            destination: URL(fileURLWithPath: "/tmp/ob")
        )
        #expect(!areCompatible(a, b, probe: StubProbe()))
    }

    @Test("Predicate allows parallel on internal SSD, different destinations, no password input")
    func predicate_allowsParallel_ifInternalSSD_differentDest_noPassword() {
        let a = PendingJob(
            job: ArchiveJob(url: URL(fileURLWithPath: "/tmp/a.zip")),
            destination: URL(fileURLWithPath: "/tmp/oa")
        )
        let b = PendingJob(
            job: ArchiveJob(url: URL(fileURLWithPath: "/tmp/b.zip")),
            destination: URL(fileURLWithPath: "/tmp/ob")
        )
        #expect(areCompatible(a, b, probe: StubProbe()))
    }

    // MARK: - Scheduler

    @Test("Scheduler caps maxParallel at min(cpuCount, 4)")
    func scheduler_caps_at_min_cpuCount_and_4() {
        let app = AppModel()
        let probe = StubProbe()

        let big = Scheduler(model: app, probe: probe, cpuCount: { 32 })
        #expect(big.maxParallel == 4)

        let small = Scheduler(model: app, probe: probe, cpuCount: { 2 })
        #expect(small.maxParallel == 2)

        let one = Scheduler(model: app, probe: probe, cpuCount: { 1 })
        #expect(one.maxParallel == 1)
    }

    @Test("Scheduler picks the first compatible queued job when a slot opens")
    func scheduler_picksFirstCompatible_fromQueue() {
        let app = AppModel()
        // Three URLs: a, b, c. a/b share destination → block each other.
        // b/c also share. a/c are compatible.
        let dirAB = URL(fileURLWithPath: "/tmp/shared")
        let aURL = dirAB.appendingPathComponent("a.zip")
        let bURL = dirAB.appendingPathComponent("b.zip")
        let cURL = URL(fileURLWithPath: "/tmp/elsewhere/c.zip")
        app.enqueue(urls: [aURL, bURL, cURL])

        let probe = StubProbe()
        let scheduler = Scheduler(model: app, probe: probe, maxParallel: 4, cpuCount: { 4 })

        // Simulate: a is running.
        let a = app.queue[0]
        a.updateState(.running)
        scheduler.markActive(a, destination: dirAB)

        // Pick next compatible — should be c (b would clash with a's dest).
        let picked = scheduler.pickCompatibleQueuedJob()
        #expect(picked?.job.url == cURL.standardizedFileURL)
        #expect(picked?.destination == cURL.standardizedFileURL.deletingLastPathComponent())
    }
}
