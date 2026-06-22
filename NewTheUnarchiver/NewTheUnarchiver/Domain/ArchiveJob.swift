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
        progress = p
    }
}
