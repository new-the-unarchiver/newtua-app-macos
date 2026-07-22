import Foundation
import Newtua
@testable import NewTheUnarchiver

/// Shared scaffolding for app-side tests: fixture locations and temp-dir helpers.
enum TestSupport {
    /// Directory holding the Xcode project, derived from this file's location.
    /// Layout: <project dir>/NewTheUnarchiverTests/TestSupport.swift
    static func projectDir() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<2 { url.deleteLastPathComponent() }
        return url
    }

    /// Path to a committed archive fixture by name.
    ///
    /// The fixtures are copies of `newtua-core/tests/fixtures` taken when the
    /// app moved into its own repository — the engine now lives in a separate
    /// repo, so the app carries its own copies to stay self-contained.
    static func fixture(_ name: String) -> URL {
        projectDir()
            .appendingPathComponent("TestFixtures")
            .appendingPathComponent(name)
    }

    /// A fresh temporary directory the caller owns. Caller is responsible for
    /// deletion (use `defer { try? FileManager.default.removeItem(at: dir) }`).
    static func makeTempDir(prefix: String = "newtua-app-test") throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Build a `Newtua.Progress` snapshot with sensible defaults — cuts the
    /// constructor noise in throttle tests.
    static func tick(
        bytes: UInt64,
        of size: UInt64 = 1000,
        index: Int = 0,
        path: String = "a",
        started: Bool = false,
        finished: Bool = false
    ) -> Newtua.Progress {
        Newtua.Progress(
            index: index,
            path: path,
            bytesWritten: bytes,
            entrySize: size,
            started: started,
            finished: finished
        )
    }

    /// Build a job already in `.running` with entry sizes registered —
    /// the typical setup for any test that pokes `recordProgress`.
    @MainActor
    static func runningJob(
        url: URL = URL(fileURLWithPath: "/tmp/test.zip"),
        sizes: [UInt64]
    ) -> ArchiveJob {
        let job = ArchiveJob(url: url)
        job.updateState(.running)
        job.setEntries(sizes: sizes)
        return job
    }

    /// Isolated `UserDefaults` suite for tests that mutate `AppModel`'s
    /// `extractionOptions`. Pair with the returned `teardown` closure (via
    /// `defer`) — otherwise stale state leaks into the next test.
    struct IsolatedDefaults {
        let defaults: UserDefaults
        let teardown: @Sendable () -> Void
    }

    static func isolatedDefaults() -> IsolatedDefaults {
        let suite = "newtua-app-test-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        return IsolatedDefaults(defaults: d) {
            d.removePersistentDomain(forName: suite)
        }
    }
}

/// Records calls to `PostExtractActions` without touching Finder or the
/// real Trash.
@MainActor
final class StubPostExtractActions: PostExtractActions {
    var openedFolders: [URL] = []
    var movedToTrash: [URL] = []

    func openFolder(_ url: URL) {
        openedFolders.append(url)
    }

    func moveToTrash(_ url: URL) {
        movedToTrash.append(url)
    }
}

/// Pre-programmed `DestinationPrompter` for Stage 8 tests. Returns the URL
/// pre-set for a given archive, or `nil` to simulate the user cancelling.
/// Records every prompt the coordinator issued so tests can assert ordering.
@MainActor
final class StubDestinationPrompter: DestinationPrompter {
    /// `nil` value (set with `responses[url] = .none`) simulates cancel.
    var responses: [URL: URL?] = [:]
    var asked: [URL] = []

    func promptForDestination(archive: URL) -> URL? {
        asked.append(archive)
        return responses[archive] ?? nil
    }
}

/// In-memory `FileAssociationsService` used by Stage 7 tests. `init(initial:)`
/// seeds the backing map; `shouldThrowOnSet` lets a test force the next
/// `setDefaultHandler` to fail without a second stub class.
@MainActor
final class StubFileAssociationsService: FileAssociationsService {
    struct Boom: Error, Equatable {}

    var shouldThrowOnSet: Bool = false
    private var map: [String: String]

    init(initial: [String: String] = [:]) {
        self.map = initial
    }

    func defaultHandler(forUTI uti: String) -> String? {
        map[uti]
    }

    func setDefaultHandler(_ bundleID: String, forUTI uti: String) throws {
        if shouldThrowOnSet { throw Boom() }
        map[uti] = bundleID
    }

    /// Mutate the backing store without going through the protocol — used by
    /// `refresh` tests to simulate a Finder-side change.
    func externalSet(_ uti: String, bundleID: String) {
        map[uti] = bundleID
    }
}
