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
            let standardized = url.standardizedFileURL
            guard !active.contains(standardized) else { continue }
            queue.append(ArchiveJob(url: standardized))
            active.insert(standardized)
        }
    }

    func remove(_ job: ArchiveJob) {
        queue.removeAll { $0.id == job.id }
    }

    func setSharedPassword(_ password: String, applyToAll: Bool) {
        guard applyToAll else { return }
        sharedPassword = password
    }

    func clearSharedPassword() {
        sharedPassword = nil
    }
}
