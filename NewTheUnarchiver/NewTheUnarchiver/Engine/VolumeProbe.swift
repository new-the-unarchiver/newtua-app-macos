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

/// macOS implementation backed by `URLResourceValues`, with a mount-path
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
        let keys: Set<URLResourceKey> = [
            .volumeURLKey, .volumeIsInternalKey, .volumeNameKey, .volumeLocalizedFormatDescriptionKey
        ]
        let values = try? url.resourceValues(forKeys: keys)
        // Cache by the volume's mount URL — the same physical disk shows up
        // through many paths (every file on it), but the volumeURL is canonical.
        let mountKey = values?.volume?.path ?? url.path
        if let hit = cache.withLock({ $0[mountKey] }) {
            return hit
        }
        let isInternal = values?.volumeIsInternal ?? false
        let fusion = (values?.volumeLocalizedFormatDescription ?? "")
            .localizedCaseInsensitiveContains("fusion")
        let medium: VolumeMediumType = isInternal && !fusion ? .ssd : .unknown
        let reading = Reading(isInternal: isInternal, medium: medium)
        cache.withLock { $0[mountKey] = reading }
        return reading
    }
}
