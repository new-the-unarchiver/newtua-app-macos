import Foundation
import Newtua

enum PasswordReason: Sendable, Equatable {
    case encrypted
    case wrongPassword
}

enum JobState: Sendable, Equatable {
    case queued
    case running
    case needsPassword(PasswordReason)
    case needsEncoding(currentEncoding: String?)
    case succeeded(ExtractReport)
    case failed(ErrorCode)
    case cancelled

    var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .cancelled: true
        case .queued, .running, .needsPassword, .needsEncoding: false
        }
    }

    /// Permissive: only blocks leaving terminal states. The runner is the
    /// authority on target-specific validity (e.g. `.queued → .succeeded`
    /// without `.running` is allowed here but the runner won't issue it).
    func canTransition(to next: JobState) -> Bool {
        !isTerminal
    }
}
