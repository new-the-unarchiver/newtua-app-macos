import Foundation

/// A job-in-flight (or candidate) paired with its resolved destination.
/// Bundling them removes a positional-parameter footgun and keeps pick/launch
/// from re-deriving the destination independently.
@MainActor
struct PendingJob {
    let job: ArchiveJob
    let destination: URL
}

/// Pure compatibility check: can two jobs run in parallel?
///
/// Returns `false` (blocks parallel) when any of these hold (per
/// `decisions.md` 2026-06-22 "Параллельная распаковка"):
/// - The two destinations match (FS contention, wrapper-folder races).
/// - Either job is awaiting password input — that's a natural
///   serialisation point and the user has to act before progress.
/// - Either source URL is on an external volume, an HDD, or a volume the
///   probe can't classify (`.unknown` falls back to serial — safe default).
@MainActor
func areCompatible(_ a: PendingJob, _ b: PendingJob, probe: VolumeProbing) -> Bool {
    // Compare by `.path`: URL equality is trailing-slash-sensitive, but a
    // file's `deletingLastPathComponent()` adds the slash while
    // `URL(fileURLWithPath:)` for the same directory does not.
    if a.destination.standardizedFileURL.path == b.destination.standardizedFileURL.path {
        return false
    }
    if a.job.state.isAwaitingPassword || b.job.state.isAwaitingPassword {
        return false
    }
    for url in [a.job.url, b.job.url] {
        if !probe.isInternal(url) { return false }
        if probe.mediumType(url) != .ssd { return false }
    }
    return true
}
