import Foundation
import Newtua
import Testing
@testable import NewTheUnarchiver

@MainActor
@Suite("Stage 8 — apply Preferences to extraction (TDD-min)")
struct Stage8Tests {

    // MARK: - ExtractionOptions helpers

    @Test("wrapperFlag: .never and .always are false; .onlyIfMultiple is true")
    func wrapperFlag_perMode() {
        var opts = ExtractionOptions()
        opts.wrapperMode = .never
        #expect(opts.wrapperFlag == false)
        opts.wrapperMode = .onlyIfMultiple
        #expect(opts.wrapperFlag == true)
        opts.wrapperMode = .always
        #expect(opts.wrapperFlag == false)
    }

    @Test("resolvedExtractURL: .always appends the archive stem; others unchanged")
    func resolvedExtractURL_perMode() {
        var opts = ExtractionOptions()
        let base = URL(fileURLWithPath: "/tmp/out")
        let archive = URL(fileURLWithPath: "/Users/u/Downloads/photos.zip")
        opts.wrapperMode = .never
        #expect(opts.resolvedExtractURL(base: base, archive: archive) == base)
        opts.wrapperMode = .onlyIfMultiple
        #expect(opts.resolvedExtractURL(base: base, archive: archive) == base)
        opts.wrapperMode = .always
        #expect(opts.resolvedExtractURL(base: base, archive: archive).lastPathComponent == "photos")
    }

    // MARK: - ArchiveJob destinationOverride

    @Test("ArchiveJob preserves destinationOverride when supplied")
    func archiveJob_destinationOverride_isPersisted() {
        let dest = URL(fileURLWithPath: "/tmp/out")
        let job = ArchiveJob(url: URL(fileURLWithPath: "/tmp/x.zip"), destinationOverride: dest)
        #expect(job.destinationOverride == dest)
    }

    @Test("AppModel.enqueue forwards destinationOverride to every new job")
    func appModel_enqueue_forwardsOverride() {
        let app = AppModel()
        let dest = URL(fileURLWithPath: "/Users/u/Downloads")
        app.enqueue(urls: [
            URL(fileURLWithPath: "/tmp/a.zip"),
            URL(fileURLWithPath: "/tmp/b.zip"),
        ], destinationOverride: dest)
        for job in app.queue { #expect(job.destinationOverride == dest) }
    }

    // MARK: - Scheduler.resolvedDestination

    @Test("Scheduler.resolvedDestination: override wins over strategy")
    func resolvedDestination_overrideWins() {
        let app = AppModel()
        app.extractionOptions.destinationStrategy = .fixed(URL(fileURLWithPath: "/strategy"))
        app.enqueue(urls: [URL(fileURLWithPath: "/tmp/x.zip")],
                    destinationOverride: URL(fileURLWithPath: "/override"))
        let scheduler = Scheduler(model: app, probe: StubProbe(), maxParallel: 0)
        #expect(scheduler.resolvedDestination(for: app.queue[0]).path == "/override")
    }

    @Test("Scheduler.resolvedDestination: .fixed strategy used when no override")
    func resolvedDestination_strategyFixed() {
        let app = AppModel()
        app.extractionOptions.destinationStrategy = .fixed(URL(fileURLWithPath: "/strategy"))
        app.enqueue(urls: [URL(fileURLWithPath: "/tmp/x.zip")])
        let scheduler = Scheduler(model: app, probe: StubProbe(), maxParallel: 0)
        #expect(scheduler.resolvedDestination(for: app.queue[0]).path == "/strategy")
    }

    @Test("Scheduler.resolvedDestination: .nextToArchive uses defaultDestination")
    func resolvedDestination_nextToArchive() {
        let app = AppModel()
        app.extractionOptions.destinationStrategy = .nextToArchive
        let archive = URL(fileURLWithPath: "/Users/u/Downloads/photos.zip")
        app.enqueue(urls: [archive])
        let scheduler = Scheduler(model: app, probe: StubProbe(), maxParallel: 0)
        #expect(scheduler.resolvedDestination(for: app.queue[0])
                == archive.deletingLastPathComponent())
    }

    @Test("Scheduler.resolvedDestination: .askEachTime without override falls back to defaultDestination")
    func resolvedDestination_askEachTimeFallback() {
        let app = AppModel()
        app.extractionOptions.destinationStrategy = .askEachTime
        let archive = URL(fileURLWithPath: "/Users/u/Downloads/photos.zip")
        app.enqueue(urls: [archive])
        let scheduler = Scheduler(model: app, probe: StubProbe(), maxParallel: 0)
        #expect(scheduler.resolvedDestination(for: app.queue[0])
                == archive.deletingLastPathComponent())
    }

    // MARK: - JobRunner post-actions

    @Test("JobRunner: openFolderAfter triggers PostExtractActions.openFolder on success")
    func runner_openFolderAfter_onSuccess() async throws {
        let app = AppModel()
        app.enqueue(urls: [TestSupport.fixture("hello.7z")])
        let job = try #require(app.queue.first)
        let dest = try TestSupport.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dest) }

        let actions = StubPostExtractActions()
        var options = ExtractionOptions()
        options.openFolderAfter = true

        let runner = JobRunner(
            job: job,
            destination: dest,
            options: options,
            actions: actions
        )
        await runner.run()

        if case .succeeded = job.state {} else {
            Issue.record("expected .succeeded, got \(job.state)")
        }
        #expect(actions.openedFolders == [dest])
        #expect(actions.movedToTrash.isEmpty)
    }

    @Test("JobRunner: moveToTrashAfter triggers PostExtractActions.moveToTrash with the archive URL")
    func runner_moveToTrashAfter_onSuccess() async throws {
        let app = AppModel()
        let archiveURL = TestSupport.fixture("hello.7z")
        app.enqueue(urls: [archiveURL])
        let job = try #require(app.queue.first)
        let dest = try TestSupport.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dest) }

        let actions = StubPostExtractActions()
        var options = ExtractionOptions()
        options.moveToTrashAfter = true

        let runner = JobRunner(
            job: job,
            destination: dest,
            options: options,
            actions: actions
        )
        await runner.run()

        if case .succeeded = job.state {} else {
            Issue.record("expected .succeeded, got \(job.state)")
        }
        #expect(actions.movedToTrash == [archiveURL.standardizedFileURL])
        #expect(actions.openedFolders.isEmpty)
    }

    @Test("JobRunner: post-actions do not fire on failure (wrong password)")
    func runner_postActions_noFireOnFailure() async throws {
        let app = AppModel()
        app.enqueue(urls: [TestSupport.fixture("secret.zip")])
        let job = try #require(app.queue.first)
        let dest = try TestSupport.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dest) }

        let actions = StubPostExtractActions()
        var options = ExtractionOptions()
        options.openFolderAfter = true
        options.moveToTrashAfter = true

        let runner = JobRunner(
            job: job,
            destination: dest,
            options: options,
            password: "definitely-wrong",
            actions: actions
        )
        await runner.run()

        #expect(actions.openedFolders.isEmpty)
        #expect(actions.movedToTrash.isEmpty)
    }

    // MARK: - askEachTime via DestinationPrompter

    @Test("AppCoordinator: .askEachTime with prompter-cancellation does not enqueue")
    func appCoordinator_askEachTime_cancelSkips() {
        let prompter = StubDestinationPrompter()
        let iso = TestSupport.isolatedDefaults()
        defer { iso.teardown() }
        let coordinator = AppCoordinator(defaults: iso.defaults, destinationPrompter: prompter)
        coordinator.model.extractionOptions.destinationStrategy = .askEachTime

        let archive = URL(fileURLWithPath: "/tmp/x.zip")
        prompter.responses[archive.standardizedFileURL] = .none
        coordinator.openURLs([archive])

        #expect(coordinator.model.queue.isEmpty)
        #expect(prompter.asked == [archive.standardizedFileURL])
    }

    @Test("AppCoordinator: .askEachTime with prompter-acceptance enqueues with destinationOverride")
    func appCoordinator_askEachTime_acceptStoresOverride() {
        let prompter = StubDestinationPrompter()
        let iso = TestSupport.isolatedDefaults()
        defer { iso.teardown() }
        let coordinator = AppCoordinator(defaults: iso.defaults, destinationPrompter: prompter)
        coordinator.model.extractionOptions.destinationStrategy = .askEachTime

        let archive = URL(fileURLWithPath: "/tmp/x.zip")
        let dest = URL(fileURLWithPath: "/Users/u/PickedDest")
        prompter.responses[archive.standardizedFileURL] = dest
        coordinator.openURLs([archive])

        #expect(coordinator.model.queue.count == 1)
        #expect(coordinator.model.queue[0].destinationOverride == dest)
    }
}
