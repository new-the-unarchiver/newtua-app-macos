import Foundation

/// Aggregate counters shown in the preview header: how many files, how
/// many folders, total uncompressed size. Symlinks count as files —
/// Quick Look has no separate row for them in v1, and "files" is the
/// closest user-facing bucket.
struct ArchiveSummary: Equatable, Sendable {
    let files: Int
    let folders: Int
    let totalBytes: UInt64

    static let zero = ArchiveSummary(files: 0, folders: 0, totalBytes: 0)

    static func summarize(_ tree: [TreeNode]) -> ArchiveSummary {
        var files = 0
        var folders = 0
        var bytes: UInt64 = 0
        tree.walk { node in
            switch node.kind {
            case .directory: folders += 1
            case .file, .symlink:
                files += 1
                bytes &+= node.size ?? 0
            }
        }
        return ArchiveSummary(files: files, folders: folders, totalBytes: bytes)
    }
}
