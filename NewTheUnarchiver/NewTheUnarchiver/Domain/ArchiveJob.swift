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
    let cancellation: CancellationToken

    init(url: URL) {
        self.id = UUID()
        self.url = url
        self.state = .queued
        self.progress = nil
        self.cancellation = CancellationToken()
    }

    func updateState(_ next: JobState) {
        guard state.canTransition(to: next) else { return }
        state = next
    }

    func cancel() {
        cancellation.cancel()
        if !state.isTerminal {
            state = .cancelled
        }
    }

    func recordProgress(_ p: Newtua.Progress) {
        guard case .running = state else { return }
        if let prev = progress {
            // Backward ticks within one entry would jerk the bar leftwards.
            if prev.index == p.index, p.bytesWritten < prev.bytesWritten { return }
            // Identical ticks would notify @Observable for nothing — the
            // engine emits several per second per active job, so dedup early.
            if prev == p { return }
        }
        progress = p
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
