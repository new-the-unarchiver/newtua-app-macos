import Foundation

/// Sequential driver: walks `AppModel.queue` and runs one job at a time.
///
/// Walks the queue by index so jobs appended *during* a drain (the user
/// dropping more archives mid-extraction) are picked up automatically.
@MainActor
final class QueueDriver {
    let model: AppModel
    private(set) var isRunning: Bool = false

    init(model: AppModel) {
        self.model = model
    }

    /// Drains the queue. Returns once every job has reached a terminal or
    /// needs-input state. Re-callable: starting it again picks up newly
    /// queued jobs that arrived since the last drain.
    func drain() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        var cursor = 0
        while cursor < model.queue.count {
            let job = model.queue[cursor]
            cursor += 1
            guard job.state.isQueued else { continue }
            let runner = JobRunner(
                job: job,
                destination: defaultDestination(for: job),
                options: model.extractionOptions,
                password: model.sharedPassword
            )
            await runner.run()
        }
    }

    private func defaultDestination(for job: ArchiveJob) -> URL {
        job.url.deletingLastPathComponent()
    }
}
