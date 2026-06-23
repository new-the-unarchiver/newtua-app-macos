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
/// Returns `false` (blocks parallel) when any of these hold:
/// - Either job is awaiting password input — natural serialisation point.
/// - Either source URL is on an external volume, an HDD, or a volume the
///   probe can't classify (`.unknown` falls back to serial — safe default).
///
/// Same-destination is intentionally NOT a blocker (decisions.md): APFS
/// handles concurrent writes to one directory, and wrapper folders are
/// named after the archive so cross-archive name collisions are rare.
@MainActor
func areCompatible(_ a: PendingJob, _ b: PendingJob, probe: VolumeProbing) -> Bool {
    if a.job.state.isAwaitingPassword || b.job.state.isAwaitingPassword {
        return false
    }
    for url in [a.job.url, b.job.url] {
        if !probe.isInternal(url) { return false }
        if probe.mediumType(url) != .ssd { return false }
    }
    return true
}
