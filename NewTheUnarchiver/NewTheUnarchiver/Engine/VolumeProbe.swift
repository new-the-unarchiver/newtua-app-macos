import Foundation
import os.lock

/// Classification of a volume's storage medium. The predicate treats
/// `.hdd` and `.unknown` the same (no parallel) — `.unknown` is the safe
/// fallback whenever detection is uncertain.
enum VolumeMediumType: Sendable, Equatable {
    case ssd
    case hdd
    case unknown
}

/// Asks the OS about the volume backing a URL. Pure read-only contract;
/// implementations may cache by mount path.
protocol VolumeProbing: Sendable {
    func isInternal(_ url: URL) -> Bool
    func mediumType(_ url: URL) -> VolumeMediumType
}

/// macOS implementation backed by `URLResourceValues`, with a two-tier
/// cache so the same volume isn't re-queried for every job in the queue.
///
/// SSD/HDD detection on v1 is a heuristic: any internal volume is assumed
/// `.ssd` UNLESS the volume type name contains "Fusion" (legacy Intel
/// Fusion drives — SSD+HDD composites — get `.unknown` to keep them serial).
/// Anything not internal is `.unknown`, which the predicate treats as
/// serial-only. A full IOKit + Disk Arbitration probe is tracked as a
/// v1.1 improvement.
final class SystemVolumeProbe: VolumeProbing, @unchecked Sendable {
    private struct Reading {
        let isInternal: Bool
        let medium: VolumeMediumType
    }
    private let cache = OSAllocatedUnfairLock<[String: Reading]>(initialState: [:])

    init() {}

    func isInternal(_ url: URL) -> Bool {
        reading(for: url).isInternal
    }

    func mediumType(_ url: URL) -> VolumeMediumType {
        reading(for: url).medium
    }

    private func reading(for url: URL) -> Reading {
        // Hot path: same URL queried again → answer from cache, no syscall.
        if let hit = cache.withLock({ $0[url.path] }) {
            return hit
        }

        let keys: Set<URLResourceKey> = [
            .volumeURLKey, .volumeIsInternalKey, .volumeLocalizedFormatDescriptionKey
        ]
        guard
            let values = try? url.resourceValues(forKeys: keys),
            let mountURL = values.volume
        else {
            // Couldn't classify — pessimistic default, not cached. Don't cache
            // here: every bogus path would otherwise grow the dictionary.
            return Reading(isInternal: false, medium: .unknown)
        }
        let mountKey = mountURL.path
        // Mount-keyed hit: same volume seen via a different file URL.
        if let hit = cache.withLock({ $0[mountKey] }) {
            cache.withLock { $0[url.path] = hit }
            return hit
        }
        let isInternal = values.volumeIsInternal ?? false
        let fusion = (values.volumeLocalizedFormatDescription ?? "")
            .localizedCaseInsensitiveContains("fusion")
        let reading = Reading(
            isInternal: isInternal,
            medium: isInternal && !fusion ? .ssd : .unknown
        )
        cache.withLock {
            $0[mountKey] = reading
            $0[url.path] = reading
        }
        return reading
    }
}
