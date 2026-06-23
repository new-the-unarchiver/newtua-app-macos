import Foundation
import Newtua
import Testing
@testable import NewTheUnarchiver

@MainActor
@Suite("Stage 8 — apply Preferences to extraction (extended)")
struct Stage8ExtendedTests {

    // MARK: - ExtractionOptions edges

    @Test("resolvedExtractURL: archive without an extension still produces a sensible stem")
    func resolvedExtractURL_noExtension() {
        var opts = ExtractionOptions()
        opts.wrapperMode = .always
        let base = URL(fileURLWithPath: "/tmp/out")
        let archive = URL(fileURLWithPath: "/tmp/archive_no_ext")
        let resolved = opts.resolvedExtractURL(base: base, archive: archive, topLevelCount: 1)
        #expect(resolved.lastPathComponent == "archive_no_ext")
    }

    @Test("resolvedExtractURL: compound extension (.tar.gz) strips only the final component")
    func resolvedExtractURL_compoundExtension() {
        var opts = ExtractionOptions()
        opts.wrapperMode = .always
        let base = URL(fileURLWithPath: "/tmp/out")
        let archive = URL(fileURLWithPath: "/tmp/foo.tar.gz")
        // `deletingPathExtension()` strips just `.gz` — single-folder name,
        // double-extension preserved inside.
        let resolved = opts.resolvedExtractURL(base: base, archive: archive, topLevelCount: 1)
        #expect(resolved.lastPathComponent == "foo.tar")
    }

    // MARK: - JobRunner: `.always` really creates the wrapper folder

    @Test("JobRunner: wrapperMode .always extracts into <base>/<stem>/ on disk")
    func runner_wrapperAlways_writesIntoStemFolder() async throws {
        let app = AppModel()
        let archiveURL = TestSupport.fixture("hello.7z")
        app.enqueue(urls: [archiveURL])
        let job = try #require(app.queue.first)
        let dest = try TestSupport.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dest) }

        var options = ExtractionOptions()
        options.wrapperMode = .always
        let runner = JobRunner(job: job, destination: dest, options: options)
        await runner.run()

        if case .succeeded = job.state {} else {
            Issue.record("expected .succeeded, got \(job.state)")
        }
        let stem = archiveURL.deletingPathExtension().lastPathComponent
        let wrapperURL = dest.appendingPathComponent(stem)
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: wrapperURL.path, isDirectory: &isDir))
        #expect(isDir.boolValue, "wrapper must be a directory")
    }

    @Test("JobRunner: openFolder URL points at the wrapper folder under wrapperMode .always")
    func runner_openFolder_pointsAtWrapper_forAlways() async throws {
        let app = AppModel()
        let archiveURL = TestSupport.fixture("hello.7z")
        app.enqueue(urls: [archiveURL])
        let job = try #require(app.queue.first)
        let dest = try TestSupport.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dest) }

        let actions = StubPostExtractActions()
        var options = ExtractionOptions()
        options.wrapperMode = .always
        options.openFolderAfter = true
        let runner = JobRunner(
            job: job, destination: dest, options: options, actions: actions
        )
        await runner.run()

        let stem = archiveURL.deletingPathExtension().lastPathComponent
        #expect(actions.openedFolders.map(\.path)
                == [dest.appendingPathComponent(stem).path])
    }

    // MARK: - AppCoordinator askEachTime edges

    @Test("AppCoordinator: mixed batch under .askEachTime keeps the accepted archives")
    func appCoordinator_askEachTime_mixedBatch() {
        let prompter = StubDestinationPrompter()
        let iso = TestSupport.isolatedDefaults()
        defer { iso.teardown() }
        let coordinator = AppCoordinator(defaults: iso.defaults, destinationPrompter: prompter)
        coordinator.model.extractionOptions.destinationStrategy = .askEachTime

        let a = URL(fileURLWithPath: "/tmp/a.zip")
        let b = URL(fileURLWithPath: "/tmp/b.zip")
        let c = URL(fileURLWithPath: "/tmp/c.zip")
        let destB = URL(fileURLWithPath: "/Users/u/B")
        prompter.responses = [
            a.standardizedFileURL: .none,           // user cancels for `a`
            b.standardizedFileURL: destB,           // user picks for `b`
            c.standardizedFileURL: .none,           // user cancels for `c`
        ]

        coordinator.openURLs([a, b, c])

        #expect(coordinator.model.queue.count == 1)
        #expect(coordinator.model.queue[0].url == b.standardizedFileURL)
        #expect(coordinator.model.queue[0].destinationOverride == destB)
        #expect(prompter.asked.count == 3, "every archive in the batch is prompted")
    }

    @Test("AppCoordinator: .fixed does not invoke the prompter")
    func appCoordinator_fixed_neverPrompts() {
        let prompter = StubDestinationPrompter()
        let iso = TestSupport.isolatedDefaults()
        defer { iso.teardown() }
        let coordinator = AppCoordinator(defaults: iso.defaults, destinationPrompter: prompter)
        coordinator.model.extractionOptions.destinationStrategy =
            .fixed(URL(fileURLWithPath: "/Users/u/Out"))

        coordinator.openURLs([URL(fileURLWithPath: "/tmp/x.zip")])

        #expect(prompter.asked.isEmpty)
        #expect(coordinator.model.queue.count == 1)
        #expect(coordinator.model.queue[0].destinationOverride?.path == "/Users/u/Out")
    }

    @Test("AppCoordinator: directories are filtered before the prompter ever sees them")
    func appCoordinator_dirsAreFilteredBeforePrompt() {
        let prompter = StubDestinationPrompter()
        let iso = TestSupport.isolatedDefaults()
        defer { iso.teardown() }
        let coordinator = AppCoordinator(defaults: iso.defaults, destinationPrompter: prompter)
        coordinator.model.extractionOptions.destinationStrategy = .askEachTime

        let folder = URL(fileURLWithPath: "/tmp/folder", isDirectory: true)
        coordinator.openURLs([folder])

        #expect(prompter.asked.isEmpty,
                "showing a destination panel for a folder we won't extract is UX noise")
        #expect(coordinator.model.queue.isEmpty)
    }

    // MARK: - JobRunner: post-actions don't fire on cancellation

    @Test("JobRunner: post-actions do not fire when run() exits via cancellation")
    func runner_postActions_noFireOnCancel() async throws {
        let app = AppModel()
        app.enqueue(urls: [TestSupport.fixture("hello.7z")])
        let job = try #require(app.queue.first)
        job.cancel() // pre-cancel; runner exits early without engine work
        let dest = try TestSupport.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dest) }

        let actions = StubPostExtractActions()
        var options = ExtractionOptions()
        options.openFolderAfter = true
        options.moveToTrashAfter = true
        let runner = JobRunner(
            job: job, destination: dest, options: options, actions: actions
        )
        await runner.run()

        #expect(job.state == .cancelled)
        #expect(actions.openedFolders.isEmpty)
        #expect(actions.movedToTrash.isEmpty)
    }
}
