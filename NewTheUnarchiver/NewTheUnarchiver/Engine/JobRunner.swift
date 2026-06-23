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
        let wrapper = options.wrapperFlag
        let extractURL = options.resolvedExtractURL(base: destination, archive: job.url)
        // `.always` writes into `<base>/<stem>/`; create it before handing
        // the path to the engine so file ops don't race the directory's
        // existence check.
        try? FileManager.default.createDirectory(
            at: extractURL, withIntermediateDirectories: true
        )
        let destPath = extractURL.path
        let token = job.cancellation
        let throttle = self.throttle
        let job = self.job

        do {
            let archive = try await onQueue {
                try Archive(path: path, password: pw, encoding: enc)
            }
            let entrySizes: [UInt64] = try await onQueue {
                archive.entries().map(\.size)
            }
            job.setEntries(sizes: entrySizes)
            let report = try await onQueue {
                let r = try archive.extract(
                    to: destPath,
                    wrapper: wrapper,
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
}
