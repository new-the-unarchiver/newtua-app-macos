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

    func canTransition(to next: JobState) -> Bool {
        !isTerminal
    }
}
