import Foundation
import Newtua

/// Pure projection of `ArchiveJob` into the fields the row view renders.
/// `subtitleKind` is an enum (not a localized string) so tests stay
/// locale-independent — the view turns the kind into a `Text(...)` key.
struct JobRowDisplay: Equatable {
    enum SubtitleKind: Equatable {
        case queued
        case running(currentPath: String?)
        case needsPassword(PasswordReason)
        case needsEncoding
        case succeeded(ExtractReport)
        case failed(ErrorCode)
        case cancelled
    }

    let title: String
    let subtitleKind: SubtitleKind
    let progressFraction: Double?
    let showsCancelButton: Bool

    @MainActor
    init(job: ArchiveJob) {
        self.title = job.displayName
        var fraction: Double? = nil
        switch job.state {
        case .queued:
            self.subtitleKind = .queued
            self.showsCancelButton = true
        case .running:
            self.subtitleKind = .running(currentPath: job.progress?.path)
            fraction = job.overallFraction
            self.showsCancelButton = true
        case .needsPassword(let reason):
            self.subtitleKind = .needsPassword(reason)
            self.showsCancelButton = true
        case .needsEncoding:
            self.subtitleKind = .needsEncoding
            self.showsCancelButton = true
        case .succeeded(let report):
            self.subtitleKind = .succeeded(report)
            self.showsCancelButton = false
        case .failed(let code):
            self.subtitleKind = .failed(code)
            self.showsCancelButton = false
        case .cancelled:
            self.subtitleKind = .cancelled
            self.showsCancelButton = false
        }
        self.progressFraction = fraction
    }
}
