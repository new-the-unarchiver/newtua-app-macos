import Foundation
import Newtua
@testable import NewTheUnarchiver

/// Shared scaffolding for app-side tests: fixture locations and temp-dir helpers.
///
/// Mirrors `bindings/swift/Tests/NewtuaTests/TestSupport.swift`. Keep both in
/// sync — they intentionally do not share a module to avoid pulling test
/// scaffolding into the Newtua package's public surface.
enum TestSupport {
    /// Repository root, derived from this file's location.
    /// Layout: <repo>/apps/macos/NewTheUnarchiver/NewTheUnarchiverTests/TestSupport.swift
    static func repoRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }

    /// Path to a committed engine fixture by name.
    static func fixture(_ name: String) -> URL {
        repoRoot()
            .appendingPathComponent("crates/newtua-core/tests/fixtures")
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
}
