import Foundation
import Newtua
import Observation

@MainActor
@Observable
final class ArchiveJob: Identifiable {
    let id: UUID
    let url: URL
    private(set) var state: JobState
    private(set) var progress: Newtua.Progress?
    /// Aggregate progress across the whole archive, 0…1. `nil` while total
    /// size is unknown — the row falls back to the indeterminate spinner.
    private(set) var overallFraction: Double?
    /// One-shot password attached by the user via the inline prompt. The
    /// runner reads it on next launch and falls back to `AppModel.sharedPassword`.
    private(set) var pendingPassword: String?
    /// One-shot encoding override attached by the user via the inline prompt.
    private(set) var pendingEncoding: String?
    let cancellation: CancellationToken

    private var entryByteOffsets: [UInt64] = []
    private var totalBytes: UInt64 = 0

    init(url: URL) {
        self.id = UUID()
        self.url = url
        self.state = .queued
        self.progress = nil
        self.overallFraction = nil
        self.pendingPassword = nil
        self.pendingEncoding = nil
        self.cancellation = CancellationToken()
    }

    func attachPendingPassword(_ password: String?) {
        guard pendingPassword != password else { return }
        pendingPassword = password
    }

    func attachPendingEncoding(_ encoding: String?) {
        guard pendingEncoding != encoding else { return }
        pendingEncoding = encoding
    }

    /// Attach a one-shot password and move the job back to `.queued` so the
    /// scheduler picks it up. Single invariant point — used both by the
    /// directly-submitted job and by Apply-to-All fan-out.
    func requeue(withPassword password: String?) {
        attachPendingPassword(password)
        updateState(.queued)
    }

    func requeue(withEncoding encoding: String?) {
        attachPendingEncoding(encoding)
        updateState(.queued)
    }

    func updateState(_ next: JobState) {
        guard state != next, state.canTransition(to: next) else { return }
        state = next
    }

    func cancel() {
        cancellation.cancel()
        if !state.isTerminal {
            state = .cancelled
        }
    }

    func setEntries(sizes: [UInt64]) {
        var offsets: [UInt64] = []
        offsets.reserveCapacity(sizes.count)
        var acc: UInt64 = 0
        for s in sizes {
            offsets.append(acc)
            acc &+= s
        }
        self.entryByteOffsets = offsets
        self.totalBytes = acc
    }

    func recordProgress(_ p: Newtua.Progress) {
        guard case .running = state else { return }
        // Identical ticks would notify @Observable for nothing — the engine
        // emits several per second per active job, so dedup early.
        if let prev = progress, prev == p { return }
        progress = p
        guard totalBytes > 0 else { return }
        let i = max(0, p.index)
        let before: UInt64 = i < entryByteOffsets.count ? entryByteOffsets[i] : totalBytes
        let completed = before &+ p.bytesWritten
        let f = min(1.0, Double(completed) / Double(totalBytes))
        // Skip equal or backward overall fractions — saves a @Observable
        // notification when only the entry index / path advanced.
        if let prev = overallFraction, f <= prev { return }
        overallFraction = f
    }

    /// Filename shown to the user. One source of truth for the queue row,
    /// password prompt header, notifications, etc.
    var displayName: String {
        url.lastPathComponent
    }

    var defaultDestination: URL {
        url.deletingLastPathComponent()
    }
}
