import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    /// Key under which `ExtractionOptions` is persisted as JSON.
    static let extractionOptionsKey = "newtua.extractionOptions"

    private(set) var queue: [ArchiveJob] = []
    private(set) var sharedPassword: String?
    var extractionOptions: ExtractionOptions {
        didSet {
            guard extractionOptions != oldValue else { return }
            persistExtractionOptions()
        }
    }

    /// How long a terminal row stays visible before it auto-removes. `nil`
    /// disables auto-removal — used by tests that assert queue contents
    /// after a drain.
    let terminalDisplayDelay: TimeInterval?

    private let defaults: UserDefaults

    init(terminalDisplayDelay: TimeInterval? = nil, defaults: UserDefaults = .standard) {
        self.terminalDisplayDelay = terminalDisplayDelay
        self.defaults = defaults
        self.extractionOptions = Self.loadExtractionOptions(from: defaults) ?? ExtractionOptions()
    }

    private static func loadExtractionOptions(from defaults: UserDefaults) -> ExtractionOptions? {
        guard let data = defaults.data(forKey: extractionOptionsKey) else { return nil }
        // Corrupt or stale schema → fall back to defaults silently; the user
        // can re-set preferences from the UI. Crashing here would lock the
        // user out of their own app.
        return try? JSONDecoder().decode(ExtractionOptions.self, from: data)
    }

    private func persistExtractionOptions() {
        guard let data = try? JSONEncoder().encode(extractionOptions) else { return }
        defaults.set(data, forKey: Self.extractionOptionsKey)
    }

    func enqueue(urls: [URL], destinationOverride: URL? = nil) {
        var active = Set(
            queue
                .filter { !$0.state.isTerminal }
                .map(\.url)
        )
        for url in urls {
            guard Self.isEnqueueable(url) else { continue }
            let standardized = url.standardizedFileURL
            guard !active.contains(standardized) else { continue }
            queue.append(ArchiveJob(url: standardized, destinationOverride: destinationOverride))
            active.insert(standardized)
        }
    }

    /// `onOpenURLs` can in principle deliver any URL the system routes to us
    /// (custom schemes if we ever declare any in `CFBundleURLTypes`). The
    /// engine only handles local files; reject everything else. Finder always
    /// sets a trailing slash on directory URLs, so `hasDirectoryPath` is
    /// sufficient — no need for a disk-touching `isDirectoryKey` lookup on
    /// the drop hot path.
    private static func isEnqueueable(_ url: URL) -> Bool {
        url.isFileURL && !url.hasDirectoryPath
    }

    func remove(_ job: ArchiveJob) {
        queue.removeAll { $0.id == job.id }
    }

    /// Cancel a job. A still-queued job is removed from the queue right
    /// away. For non-queued cases we also fire `handleTerminal` because the
    /// scheduler only fires it from inside the runner's `Task` — for jobs
    /// parked in `.needsPassword`/`.needsEncoding` the runner has already
    /// unwound, so without this call the `.cancelled` row would stick.
    /// `handleTerminal` is idempotent (idle no-op when `terminalDisplayDelay`
    /// is `nil`; doubled `remove` calls are harmless).
    func cancel(_ job: ArchiveJob) {
        let wasQueued = job.state.isQueued
        job.cancel()
        if wasQueued {
            remove(job)
        } else {
            handleTerminal(job)
        }
    }

    /// Schedule the row to drop after `terminalDisplayDelay`. Mirrors the
    /// original Unarchiver behaviour where completed rows fade away.
    ///
    /// Safe to call twice for the same job — the `cancel` path fires it,
    /// and the scheduler's Task fires it again when the runner unwinds for
    /// a `.running` cancellation. The `queue.contains` guard skips the
    /// second background `Task` when the first one has already removed
    /// the row.
    func handleTerminal(_ job: ArchiveJob) {
        guard let delay = terminalDisplayDelay, delay > 0 else { return }
        guard queue.contains(where: { $0.id == job.id }) else { return }
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
