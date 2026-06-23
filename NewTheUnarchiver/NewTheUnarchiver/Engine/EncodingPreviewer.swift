import Foundation
import Newtua

/// Opens an archive under a candidate filename encoding and returns the
/// first non-empty entry path — what the inline encoding prompt shows as
/// `Result:`. Lives in `Engine/` so the View layer stays free of
/// `import Newtua` (and free of `Archive`'s thread-safety contract).
///
/// Operates off the calling actor — every call spins a fresh `Archive`
/// on a detached `Task`, then drops it. The `Archive`'s own per-instance
/// queue keeps it single-threaded; concurrent previews against the same
/// path are independent instances.
enum EncodingPreviewer {
    /// Returns the first non-empty `path` field of an archive entry, or
    /// `nil` on engine error / empty archive / honored cancellation.
    static func firstFilename(for url: URL, encoding: String?) async -> String? {
        await Task.detached(priority: .userInitiated) {
            if Task.isCancelled { return nil }
            guard let archive = try? Archive(path: url.path, encoding: encoding) else {
                return nil
            }
            if Task.isCancelled { return nil }
            // Walk entries one at a time rather than materializing the whole
            // `[Entry]`: a 50k-file archive would otherwise allocate every
            // path string just to find the first non-empty one.
            for i in 0..<archive.count {
                if Task.isCancelled { return nil }
                if let entry = archive.entry(at: i), !entry.path.isEmpty {
                    return entry.path
                }
            }
            return nil
        }.value
    }
}
