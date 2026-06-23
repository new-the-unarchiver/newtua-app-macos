import Foundation

/// A single node in the rendered archive tree. Built by `ArchiveTreeBuilder`,
/// consumed by `HTMLPreviewRenderer`. Synthesized intermediate directories
/// (paths that imply a folder without an explicit entry for it) have
/// `size == nil` and `mtime == nil`.
struct TreeNode: Equatable, Sendable {
    enum Kind: Sendable, Equatable {
        case file
        case directory
        case symlink
    }

    let name: String
    let path: String
    let kind: Kind
    let size: UInt64?
    let mtime: Date?
    let children: [TreeNode]

    static func file(name: String, path: String, size: UInt64, mtime: Date?) -> TreeNode {
        TreeNode(name: name, path: path, kind: .file, size: size, mtime: mtime, children: [])
    }

    static func directory(
        name: String, path: String, mtime: Date?, children: [TreeNode]
    ) -> TreeNode {
        TreeNode(
            name: name, path: path, kind: .directory,
            size: nil, mtime: mtime, children: children
        )
    }

    static func symlink(name: String, path: String, size: UInt64, mtime: Date?) -> TreeNode {
        TreeNode(name: name, path: path, kind: .symlink, size: size, mtime: mtime, children: [])
    }
}
