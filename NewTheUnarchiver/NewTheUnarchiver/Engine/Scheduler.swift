import Foundation

/// Concurrent driver that walks `AppModel.queue` and runs up to `maxParallel`
/// compatible jobs at once. Replaces Stage 2's sequential `QueueDriver`.
///
/// Compatibility is decided per pair by `areCompatible(...)`. Whenever a job
/// finishes, the scheduler tries to fill the freed slot with the first queued
/// job that's compatible with every still-running job.
@MainActor
final class Scheduler {
    /// Upper bound on concurrent jobs regardless of CPU count. Mentioned in
    /// decisions.md as 4 — kept here so docstrings/tests share one source.
    static let parallelCeiling = 4

    let model: AppModel
    let probe: VolumeProbing
    let maxParallel: Int
    let actions: PostExtractActions

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
        cpuCount: () -> Int = { ProcessInfo.processInfo.activeProcessorCount },
        actions: PostExtractActions? = nil
    ) {
        self.model = model
        self.probe = probe
        self.maxParallel = maxParallel ?? max(1, min(cpuCount(), Self.parallelCeiling))
        // Same dance as `JobRunner.init`: resolve default in init body so
        // the `@MainActor` `SystemPostExtractActions.init()` runs in the
        // right context.
        self.actions = actions ?? SystemPostExtractActions()
    }

    /// Try to start as many compatible queued jobs as possible. Call after
    /// enqueueing new jobs or after any state change that might free a slot.
    func dispatch() {
        while active.count < maxParallel, let next = pickCompatibleQueuedJob() {
            launch(next)
        }
    }

    /// Suspends until no jobs are active. Useful for tests and shutdown.
    /// Snapshots the active task list each pass so newly-added actives are
    /// awaited on the next iteration; the loop exits once `active` is empty.
    func waitUntilQuiescent() async {
        while !active.isEmpty {
            let tasks = Array(active.values.map(\.task))
            for task in tasks { _ = await task.value }
        }
    }

    /// First queued job that is pair-wise compatible with every active job.
    /// Returns the pending pair (job + resolved destination) so launch
    /// doesn't re-derive it. Internal so tests can pin behaviour without
    /// spinning up Tasks.
    func pickCompatibleQueuedJob() -> PendingJob? {
        let activePairs = Array(active.values.map(\.pending))
        for job in model.queue {
            // A just-launched job's `Task` hasn't yet flipped its state to
            // `.running`, so it stays `.queued` AND lives in `active`. Without
            // skipping it here `dispatch` would re-pick it and spin forever.
            guard job.state.isQueued, active[job.id] == nil else { continue }
            let candidate = PendingJob(job: job, destination: resolvedDestination(for: job))
            let compatible = activePairs.allSatisfy { a in
                areCompatible(a, candidate, probe: probe)
            }
            if compatible { return candidate }
        }
        return nil
    }

    /// Per-job override (set by the `.askEachTime` drop flow) wins; otherwise
    /// resolve through the global `destinationStrategy`. `.askEachTime`
    /// without an override falls back to "next to archive" — should not
    /// happen in practice because `AppCoordinator` always prompts first.
    func resolvedDestination(for job: ArchiveJob) -> URL {
        if let override = job.destinationOverride { return override }
        switch model.extractionOptions.destinationStrategy {
        case .nextToArchive, .askEachTime:
            return job.defaultDestination
        case .fixed(let url):
            return url
        }
    }

    /// Test hook: register a job as active without launching its runner.
    /// Internal-only; the `Task {}` placeholder is a no-op that completes
    /// immediately so `waitUntilQuiescent` doesn't deadlock on test fixtures.
    func markActive(_ job: ArchiveJob, destination: URL) {
        let pending = PendingJob(job: job, destination: destination)
        active[job.id] = ActiveSlot(pending: pending, task: Task {})
    }

    /// User entered a password in the inline prompt. With Apply-to-All the
    /// value is remembered on `AppModel` for future encrypted archives AND
    /// fanned out to every other job currently awaiting a password — so
    /// archives that raced into `.needsPassword` in parallel don't ask
    /// independently. Without Apply-to-All the value lives on this job only.
    func submitPassword(_ password: String, applyToAll: Bool, for job: ArchiveJob) {
        if applyToAll {
            model.setSharedPassword(password, applyToAll: true)
            for other in model.queue where other.id != job.id && other.state.isAwaitingPassword {
                other.requeue(withPassword: password)
            }
        }
        job.requeue(withPassword: password)
        dispatch()
    }

    /// User picked an encoding in the inline prompt. The value lives on the
    /// job only — encoding is per-archive (not a shared Apply-to-All), and
    /// the runner reads it on next launch.
    func submitEncoding(_ encoding: String?, for job: ArchiveJob) {
        job.requeue(withEncoding: encoding)
        dispatch()
    }

    /// Per-job override wins; otherwise fall back to the shared password the
    /// user set via Apply-to-All. Internal so tests can pin the rule without
    /// invoking the full `launch` path.
    func resolvedPassword(for job: ArchiveJob) -> String? {
        job.pendingPassword ?? model.sharedPassword
    }

    /// Per-job override wins; otherwise fall back to the global default from
    /// the Advanced preferences tab. `nil` means "let the engine auto-detect".
    func resolvedEncoding(for job: ArchiveJob) -> String? {
        job.pendingEncoding ?? model.extractionOptions.defaultEncoding
    }

    private func launch(_ pending: PendingJob) {
        let job = pending.job
        let explicit = job.pendingPassword
        let resolvedPwd = resolvedPassword(for: job)
        let runner = JobRunner(
            job: job,
            destination: pending.destination,
            options: model.extractionOptions,
            password: resolvedPwd,
            encoding: resolvedEncoding(for: job),
            passwordIsShared: explicit == nil && resolvedPwd != nil,
            actions: actions
        )
        let id = pending.job.id
        let task = Task { [weak self] in
            await runner.run()
            self?.active.removeValue(forKey: id)
            self?.model.handleTerminal(pending.job)
            self?.dispatch()
        }
        active[id] = ActiveSlot(pending: pending, task: task)
    }
}
