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
            // Directories aren't archives — silently drop so every input
            // source (drop, File ▸ Open…, double-click) shares one gate.
            guard !url.hasDirectoryPath else { continue }
            let standardized = url.standardizedFileURL
            guard !active.contains(standardized) else { continue }
            queue.append(ArchiveJob(url: standardized))
            active.insert(standardized)
        }
    }

    func remove(_ job: ArchiveJob) {
        queue.removeAll { $0.id == job.id }
    }

    /// Cancel a job; if it never started, also drop it from the queue. The
    /// "row stays visible while the runner unwinds" behaviour for running
    /// jobs is preserved (decisions.md → JobState UI rules).
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
