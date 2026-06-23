import Foundation
import Newtua

enum PasswordReason: Sendable, Equatable {
    case encrypted
    /// User typed a password and the engine said it was wrong. Show a
    /// direct "Wrong password — try again" hint.
    case wrongPassword
    /// The runner silently tried `AppModel.sharedPassword` and the engine
    /// said it was wrong. The user never typed for this archive — show
    /// a neutral "Saved password didn't match" hint instead of the red
    /// retry message.
    case sharedDidNotMatch
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

    var isQueued: Bool {
        if case .queued = self { true } else { false }
    }

    var isAwaitingPassword: Bool {
        if case .needsPassword = self { true } else { false }
    }

    /// Permissive: only blocks leaving terminal states. The runner is the
    /// authority on target-specific validity (e.g. `.queued → .succeeded`
    /// without `.running` is allowed here but the runner won't issue it).
    func canTransition(to next: JobState) -> Bool {
        !isTerminal
    }
}
