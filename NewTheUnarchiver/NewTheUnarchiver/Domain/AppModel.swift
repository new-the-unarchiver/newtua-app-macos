import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var queue: [ArchiveJob] = []
    private(set) var sharedPassword: String?
    var extractionOptions: ExtractionOptions = ExtractionOptions()

    /// How long a terminal row stays visible before it auto-removes. `nil`
    /// disables auto-removal — used by tests that assert queue contents
    /// after a drain.
    let terminalDisplayDelay: TimeInterval?

    init(terminalDisplayDelay: TimeInterval? = nil) {
        self.terminalDisplayDelay = terminalDisplayDelay
    }

    func enqueue(urls: [URL]) {
        var active = Set(
            queue
                .filter { !$0.state.isTerminal }
                .map(\.url)
        )
        for url in urls {
            // Directories aren't archives. `hasDirectoryPath` catches the
            // trailing-slash form; `isDirectoryKey` covers real-disk URLs
            // delivered without a trailing slash (File ▸ Open…, onOpenURLs).
            guard !Self.isDirectory(url) else { continue }
            let standardized = url.standardizedFileURL
            guard !active.contains(standardized) else { continue }
            queue.append(ArchiveJob(url: standardized))
            active.insert(standardized)
        }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        if url.hasDirectoryPath { return true }
        return (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    func remove(_ job: ArchiveJob) {
        queue.removeAll { $0.id == job.id }
    }

    /// Cancel a job. A still-queued job is removed from the queue right
    /// away; jobs already mid-flight (running / needsPassword / needsEncoding)
    /// stay visible until their runner unwinds and emits the terminal state.
    func cancel(_ job: ArchiveJob) {
        let wasQueued = job.state.isQueued
        job.cancel()
        if wasQueued {
            remove(job)
        }
    }

    /// Schedule the row to drop after `terminalDisplayDelay`. Mirrors the
    /// original Unarchiver behaviour where completed rows fade away.
    func handleTerminal(_ job: ArchiveJob) {
        guard let delay = terminalDisplayDelay, delay > 0 else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self else { return }
            if job.state.isTerminal {
                remove(job)
            }
        }
    }

    func setSharedPassword(_ password: String, applyToAll: Bool) {
        guard applyToAll else { return }
        sharedPassword = password
    }

    func clearSharedPassword() {
        sharedPassword = nil
    }
}
