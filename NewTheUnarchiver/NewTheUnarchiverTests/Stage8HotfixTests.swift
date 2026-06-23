import Foundation
import Newtua
import Testing
@testable import NewTheUnarchiver

@MainActor
@Suite("Stage 8 — hotfix: .onlyIfMultiple must respect single-top-level archives")
struct Stage8HotfixTests {

    // MARK: - topLevelItemCount

    @Test("topLevelItemCount: single file at root → 1")
    func tlic_singleFile() {
        #expect(JobRunner.topLevelItemCount(in: ["a.txt"]) == 1)
    }

    @Test("topLevelItemCount: multiple files at root → multiple")
    func tlic_multipleFilesAtRoot() {
        #expect(JobRunner.topLevelItemCount(in: ["a.txt", "b.txt"]) == 2)
    }

    @Test("topLevelItemCount: entries under one shared root dir → 1")
    func tlic_sharedRootDir() {
        #expect(JobRunner.topLevelItemCount(in: ["foo/a.txt", "foo/b.txt", "foo/sub/c.txt"]) == 1)
    }

    @Test("topLevelItemCount: entries split across two root dirs → 2")
    func tlic_twoRootDirs() {
        #expect(JobRunner.topLevelItemCount(in: ["foo/a.txt", "bar/b.txt"]) == 2)
    }

    @Test("topLevelItemCount: explicit directory entry counts the same as its contents")
    func tlic_explicitDirEntry() {
        // ZIP archives sometimes emit both `foo/` and `foo/a.txt`.
        #expect(JobRunner.topLevelItemCount(in: ["foo/", "foo/a.txt"]) == 1)
    }

    @Test("topLevelItemCount: empty list → 0")
    func tlic_empty() {
        #expect(JobRunner.topLevelItemCount(in: []) == 0)
    }

    // MARK: - shouldWrap

    @Test("shouldWrap: .never is false regardless of top-level count")
    func shouldWrap_never() {
        var opts = ExtractionOptions()
        opts.wrapperMode = .never
        #expect(opts.shouldWrap(topLevelCount: 0) == false)
        #expect(opts.shouldWrap(topLevelCount: 1) == false)
        #expect(opts.shouldWrap(topLevelCount: 5) == false)
    }

    @Test("shouldWrap: .always is true regardless of top-level count")
    func shouldWrap_always() {
        var opts = ExtractionOptions()
        opts.wrapperMode = .always
        #expect(opts.shouldWrap(topLevelCount: 0) == true)
        #expect(opts.shouldWrap(topLevelCount: 1) == true)
        #expect(opts.shouldWrap(topLevelCount: 5) == true)
    }

    @Test("shouldWrap: .onlyIfMultiple is true only when more than one top-level item")
    func shouldWrap_onlyIfMultiple_threshold() {
        var opts = ExtractionOptions()
        opts.wrapperMode = .onlyIfMultiple
        #expect(opts.shouldWrap(topLevelCount: 0) == false)
        #expect(opts.shouldWrap(topLevelCount: 1) == false)
        #expect(opts.shouldWrap(topLevelCount: 2) == true)
        #expect(opts.shouldWrap(topLevelCount: 99) == true)
    }

    // MARK: - Integration: hello.7z (single file) under .onlyIfMultiple

    @Test("JobRunner: .onlyIfMultiple on a single-file archive extracts flat — no wrapper folder")
    func runner_onlyIfMultiple_singleFile_extractsFlat() async throws {
        let app = AppModel()
        let archiveURL = TestSupport.fixture("hello.7z")
        app.enqueue(urls: [archiveURL])
        let job = try #require(app.queue.first)
        let dest = try TestSupport.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dest) }

        var options = ExtractionOptions()
        options.wrapperMode = .onlyIfMultiple
        let runner = JobRunner(job: job, destination: dest, options: options)
        await runner.run()

        if case .succeeded = job.state {} else {
            Issue.record("expected .succeeded, got \(job.state)")
        }

        // `hello.7z` contains the single entry `a.txt`. With
        // `.onlyIfMultiple` the original Unarchiver leaves a single
        // top-level item flat — no wrapper.
        let flatFile = dest.appendingPathComponent("a.txt")
        #expect(
            FileManager.default.fileExists(atPath: flatFile.path),
            "single-file archive must land at <dest>/a.txt"
        )
        let unexpectedWrapper = dest.appendingPathComponent("hello")
        #expect(
            !FileManager.default.fileExists(atPath: unexpectedWrapper.path),
            "no wrapper folder should appear for a single-top-level archive"
        )
    }
}
