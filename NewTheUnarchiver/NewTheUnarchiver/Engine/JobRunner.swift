import Foundation
import Newtua

/// Drives a single `ArchiveJob` through open → extract → terminal state.
/// All engine work happens on a private serial `DispatchQueue` (one per job);
/// state mutations hop back to `@MainActor`.
@MainActor
final class JobRunner {
    let job: ArchiveJob
    let destination: URL
    let options: ExtractionOptions
    let password: String?

    private let queue: DispatchQueue
    private let throttle: ProgressThrottle

    init(
        job: ArchiveJob,
        destination: URL,
        options: ExtractionOptions = ExtractionOptions(),
        password: String? = nil
    ) {
        self.job = job
        self.destination = destination
        self.options = options
        self.password = password
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
        let wrapper = wrapperFlag()
        let destPath = destination.path
        let token = job.cancellation
        let throttle = self.throttle
        let job = self.job

        do {
            let archive = try await onQueue {
                try Archive(path: path, password: pw)
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
            }
        } catch let err as NewtuaError {
            switch err.code {
            case .encrypted:
                job.updateState(.needsPassword(.encrypted))
            case .wrongPassword:
                job.updateState(.needsPassword(.wrongPassword))
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

    private func wrapperFlag() -> Bool {
        switch options.wrapperMode {
        case .never: false
        case .onlyIfMultiple, .always: true
        }
    }
}
