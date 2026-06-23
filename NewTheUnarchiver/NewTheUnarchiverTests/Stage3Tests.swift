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

    @Test("Predicate allows parallel even when jobs share the same destination folder")
    func predicate_allowsParallel_ifSameDestination() {
        let dest = URL(fileURLWithPath: "/tmp/out")
        let a = PendingJob(job: ArchiveJob(url: URL(fileURLWithPath: "/tmp/a.zip")), destination: dest)
        let b = PendingJob(job: ArchiveJob(url: URL(fileURLWithPath: "/tmp/b.zip")), destination: dest)
        #expect(areCompatible(a, b, probe: StubProbe()))
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
        // Three queued URLs in separate folders. The middle archive sits on
        // an external volume, so it can't run in parallel; pick must skip
        // it and return the third.
        let urls = (0..<3).map { URL(fileURLWithPath: "/tmp/dir\($0)/x.zip") }
        app.enqueue(urls: urls)
        let probe = StubProbe(overrides: [
            urls[1].standardizedFileURL: (isInternal: false, medium: .ssd)
        ])
        let scheduler = Scheduler(model: app, probe: probe, maxParallel: 4, cpuCount: { 4 })

        let zero = app.queue[0]
        zero.updateState(.running)
        scheduler.markActive(zero, destination: zero.defaultDestination)

        let picked = scheduler.pickCompatibleQueuedJob()
        #expect(picked?.job.url == urls[2].standardizedFileURL)
    }
}
