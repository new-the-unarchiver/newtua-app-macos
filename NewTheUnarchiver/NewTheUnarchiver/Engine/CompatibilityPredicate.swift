import Foundation

/// A job-in-flight (or candidate) paired with its resolved destination.
/// Bundling them removes a positional-parameter footgun and keeps pick/launch
/// from re-deriving the destination independently.
@MainActor
struct PendingJob {
    let job: ArchiveJob
    let destination: URL

    init(job: ArchiveJob, destination: URL) {
        self.job = job
        self.destination = destination
    }

    /// Convenience: use the job's default ("next to archive") destination.
    init(_ job: ArchiveJob) {
        self.init(job: job, destination: job.defaultDestination)
    }
}

/// Pure compatibility check: can two jobs run in parallel?
///
/// Returns `false` (blocks parallel) when any of these hold:
/// - Either job is awaiting password input — that's a natural
///   serialisation point and the user has to act before progress.
/// - Either source URL is on an external volume, an HDD, or a volume the
///   probe can't classify (`.unknown` falls back to serial — safe default).
///
/// Same-destination is NOT a blocker: APFS handles concurrent writes to
/// the same parent directory fine, and the per-archive wrapper folders
/// are named after the archive so cross-archive collisions are vanishingly
/// rare. The original Unarchiver didn't parallelise at all — we trade an
/// over-cautious wrapper-name race for a real UX win on M-series machines.
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
