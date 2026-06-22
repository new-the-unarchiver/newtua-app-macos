import Foundation

/// Concurrent driver that walks `AppModel.queue` and runs up to `maxParallel`
/// compatible jobs at once. Replaces Stage 2's sequential `QueueDriver`.
///
/// Compatibility is decided per pair by `areCompatible(...)`. Whenever a job
/// finishes, the scheduler tries to fill the freed slot with the first queued
/// job that's compatible with every still-running job.
@MainActor
final class Scheduler {
    let model: AppModel
    let probe: VolumeProbing
    let maxParallel: Int

    private struct ActiveSlot {
        let pending: PendingJob
        let task: Task<Void, Never>
    }
    private var active: [UUID: ActiveSlot] = [:]

    /// Number of jobs currently occupying a slot. Useful for tests and for
    /// the queue UI badge.
    var activeCount: Int { active.count }

    init(
        model: AppModel,
        probe: VolumeProbing = SystemVolumeProbe(),
        maxParallel: Int? = nil,
        cpuCount: () -> Int = { ProcessInfo.processInfo.activeProcessorCount }
    ) {
        self.model = model
        self.probe = probe
        self.maxParallel = maxParallel ?? max(1, min(cpuCount(), 4))
    }

    /// Try to start as many compatible queued jobs as possible. Call after
    /// enqueueing new jobs or after any state change that might free a slot.
    func dispatch() {
        while active.count < maxParallel, let next = pickCompatibleQueuedJob() {
            launch(next)
        }
    }

    /// Suspends until no jobs are active. Useful for tests and shutdown.
    func waitUntilQuiescent() async {
        while let task = active.values.first?.task {
            _ = await task.value
        }
    }

    /// First queued job that is pair-wise compatible with every active job.
    /// Returns the pending pair (job + resolved destination) so launch
    /// doesn't re-derive it. Internal so tests can pin behaviour without
    /// spinning up Tasks.
    func pickCompatibleQueuedJob() -> PendingJob? {
        let activePairs = Array(active.values.map(\.pending))
        for job in model.queue {
            guard job.state.isQueued else { continue }
            let candidate = PendingJob(job: job, destination: job.defaultDestination)
            let compatible = activePairs.allSatisfy { a in
                areCompatible(a, candidate, probe: probe)
            }
            if compatible { return candidate }
        }
        return nil
    }

    /// Test hook: register a job as active without launching its runner.
    /// Internal-only; the `Task {}` placeholder is a no-op that completes
    /// immediately so `waitUntilQuiescent` doesn't deadlock on test fixtures.
    func markActive(_ job: ArchiveJob, destination: URL) {
        let pending = PendingJob(job: job, destination: destination)
        active[job.id] = ActiveSlot(pending: pending, task: Task {})
    }

    private func launch(_ pending: PendingJob) {
        let runner = JobRunner(
            job: pending.job,
            destination: pending.destination,
            options: model.extractionOptions,
            password: model.sharedPassword
        )
        let id = pending.job.id
        let task = Task { [weak self] in
            await runner.run()
            self?.active.removeValue(forKey: id)
            self?.dispatch()
        }
        active[id] = ActiveSlot(pending: pending, task: task)
    }
}
