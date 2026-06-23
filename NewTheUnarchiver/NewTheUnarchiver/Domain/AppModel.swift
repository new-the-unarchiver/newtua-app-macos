import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var queue: [ArchiveJob] = []
    private(set) var sharedPassword: String?
    var extractionOptions: ExtractionOptions = ExtractionOptions()

    init() {}

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

    func setSharedPassword(_ password: String, applyToAll: Bool) {
        guard applyToAll else { return }
        sharedPassword = password
    }

    func clearSharedPassword() {
        sharedPassword = nil
    }
}
