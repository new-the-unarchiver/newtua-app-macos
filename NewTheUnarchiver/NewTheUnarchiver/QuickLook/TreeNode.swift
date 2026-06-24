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

    /// Pre-order DFS: `visit` is called on each node before its children.
    /// Centralised so `ArchiveSummary`, `IconCatalog.uniqueCIDs`, and
    /// `HTMLPreviewRenderer.countNodes` don't each re-implement the walk.
    func walk(_ visit: (TreeNode) -> Void) {
        visit(self)
        for child in children { child.walk(visit) }
    }
}

extension Array where Element == TreeNode {
    /// Pre-order DFS over a forest.
    func walk(_ visit: (TreeNode) -> Void) {
        for node in self { node.walk(visit) }
    }
}
