import Foundation
import Newtua

/// Drives a single `ArchiveJob` through open → extract → terminal state.
/// All engine work happens on a private serial `DispatchQueue` (one per job);
/// state mutations hop back to `@MainActor`.
@MainActor
final class JobRunner {
    let job: ArchiveJob
    /// User-chosen base destination — `Scheduler.resolvedDestination(for:)`.
    /// The actual directory the engine writes into is derived via
    /// `options.resolvedExtractURL(base:archive:)` so the `.always`
    /// wrapper folder is created on the Swift side.
    let destination: URL
    let options: ExtractionOptions
    let password: String?
    let encoding: String?
    /// `true` when `password` came from `AppModel.sharedPassword` (the runner
    /// silently retried with a remembered value), `false` when the user typed
    /// it explicitly. Affects only the `.wrongPassword` vs `.sharedDidNotMatch`
    /// distinction on auth failure.
    let passwordIsShared: Bool
    let actions: PostExtractActions

    private let queue: DispatchQueue
    private let throttle: ProgressThrottle

    init(
        job: ArchiveJob,
        destination: URL,
        options: ExtractionOptions = ExtractionOptions(),
        password: String? = nil,
        encoding: String? = nil,
        passwordIsShared: Bool = false,
        actions: PostExtractActions? = nil
    ) {
        self.job = job
        self.destination = destination
        self.options = options
        self.password = password
        self.encoding = encoding
        self.passwordIsShared = passwordIsShared
        // Resolve here, not in the default value — `SystemPostExtractActions`'
        // initializer is `@MainActor`, but parameter defaults evaluate in
        // nonisolated context, which fails under strict concurrency.
        self.actions = actions ?? SystemPostExtractActions()
        self.queue = DispatchQueue(label: "newtua.job.\(job.id.uuidString)")
        self.throttle = ProgressThrottle()
    }

    /// Runs the job to completion or to a state requiring user input
    /// (`needsPassword`). On return, `job.state` is terminal, `.needsPassword`,
    /// or `.needsEncoding`. Never throws — all failures are reflected in state.
    func run() async {
        if job.cancellation.isCancelled {
            job.cancel()
            return
        }

        job.updateState(.running)

        let path = job.url.path
        let pw = password
        let enc = encoding
        let token = job.cancellation
        let throttle = self.throttle
        let job = self.job

        do {
            let archive = try await onQueue {
                try Archive(path: path, password: pw, encoding: enc)
            }
            let entries = try await onQueue { archive.entries() }
            let topLevelCount = Self.topLevelItemCount(in: entries.map(\.path))
            job.setEntries(sizes: entries.map(\.size))

            let extractURL = options.resolvedExtractURL(
                base: destination,
                archive: self.job.url,
                topLevelCount: topLevelCount
            )
            // Pre-create the wrapper dir (engine gets `wrapper: false` and
            // doesn't create it itself). `extractRan` lets us roll back an
            // empty wrapper if extract throws — otherwise the
            // verify_password contract "nothing on disk after auth failure"
            // leaks an empty `<dest>/<stem>/`. Using a success flag (not a
            // post-hoc directory scan) avoids a false negative when Finder
            // has already dropped `.DS_Store` inside an existing dest.
            let preExisted = FileManager.default.fileExists(atPath: extractURL.path)
            try? FileManager.default.createDirectory(
                at: extractURL, withIntermediateDirectories: true
            )
            var extractRan = false
            defer {
                if !preExisted, !extractRan {
                    try? FileManager.default.removeItem(at: extractURL)
                }
            }
            let destPath = extractURL.path

            let report = try await onQueue {
                let r = try archive.extract(
                    to: destPath,
                    wrapper: false,
                    cancellation: token,
                    progress: { p in
                        // Called on `queue`. Throttle here, drop ticks issued
                        // after cancellation, then hop to main.
                        guard let emit = throttle.feed(p), !token.isCancelled
                        else { return }
                        DispatchQueue.main.async {
                            job.recordProgress(emit)
                        }
                    }
                )
                if let tail = throttle.flush(), !token.isCancelled {
                    DispatchQueue.main.async {
                        job.recordProgress(tail)
                    }
                }
                return r
            }
            extractRan = true

            if report.aborted {
                job.cancel()
            } else {
                job.updateState(.succeeded(report))
                runPostActions(extractURL: extractURL)
            }
        } catch let err as NewtuaError {
            switch err.code {
            case .encrypted:
                job.updateState(.needsPassword(.encrypted))
            case .wrongPassword:
                job.updateState(.needsPassword(passwordIsShared ? .sharedDidNotMatch : .wrongPassword))
            default:
                job.updateState(.failed(err.code))
            }
        } catch {
            job.updateState(.failed(.panic))
        }
    }

    /// Run `body` on the job's serial DispatchQueue and bridge the result
    /// back to the calling `async` context. Centralises the
    /// `withCheckedThrowingContinuation + queue.async` pattern.
    private func onQueue<T: Sendable>(
        _ body: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<T, Error>) in
            queue.async {
                do { cont.resume(returning: try body()) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    /// Fired right after `.succeeded` lands on the job. Gated by
    /// `ExtractionOptions.openFolderAfter` / `.moveToTrashAfter`. Never
    /// blocks the runner — actions are fire-and-forget on the main actor.
    private func runPostActions(extractURL: URL) {
        if options.openFolderAfter {
            actions.openFolder(extractURL)
        }
        if options.moveToTrashAfter {
            actions.moveToTrash(job.url)
        }
    }

    /// Counts unique top-level path components — matches the original
    /// Unarchiver's "more than one top-level item" criterion. A single
    /// file like `a.txt`, a single dir like `foo/...`, and an explicit
    /// `foo/` + `foo/a.txt` pair all return `1`. Two siblings (file or
    /// dir) at the root return `2`. Path separator is `/` (engine
    /// guarantee), case-sensitive (matches APFS default).
    nonisolated static func topLevelItemCount(in paths: [String]) -> Int {
        var seen = Set<String>()
        for path in paths {
            guard let first = path.split(
                separator: "/", maxSplits: 1, omittingEmptySubsequences: true
            ).first else { continue }
            seen.insert(String(first))
        }
        return seen.count
    }
}
