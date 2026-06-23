import Foundation

/// Pure transform: flat archive entries → folder tree. Directories sort
/// before files, names are sorted by `localizedStandardCompare`. macOS
/// sidecar paths are silently dropped — they don't ship to disk on extract
/// (engine contract, see `MacOSSidecars`), so they shouldn't pollute the
/// preview either.
enum ArchiveTreeBuilder {

    /// Build the top-level forest. The implicit "root" is virtual — its
    /// children become the returned array.
    static func buildTree(from entries: [PreviewInputEntry]) -> [TreeNode] {
        let root = MutableNode(name: "", path: "", mtime: nil)
        for entry in entries {
            insert(entry, into: root)
        }
        return root.freeze().children
    }

    private static func insert(_ entry: PreviewInputEntry, into root: MutableNode) {
        let components = entry.path.split(separator: "/", omittingEmptySubsequences: true)
        if components.isEmpty { return }
        if components.contains(where: MacOSSidecars.matches) { return }

        var cursor = root
        var pathSoFar = ""
        for (idx, component) in components.enumerated() {
            let isLast = idx == components.count - 1
            pathSoFar = pathSoFar.isEmpty ? String(component) : pathSoFar + "/" + component
            let name = String(component)
            if let existing = cursor.children[name] {
                if isLast, entry.kind == .dir, let mtime = entry.mtime {
                    existing.mtime = mtime
                }
                cursor = existing
            } else {
                let node = makeChild(
                    name: name, path: pathSoFar,
                    entry: entry, isLast: isLast
                )
                cursor.addChild(node)
                cursor = node
            }
        }
    }

    /// Synthesizes the right `MutableNode` for one step of `insert`.
    /// Intermediate components are always directories with no size/mtime;
    /// the last component carries the entry's kind/size/mtime.
    private static func makeChild(
        name: String, path: String, entry: PreviewInputEntry, isLast: Bool
    ) -> MutableNode {
        guard isLast else {
            return MutableNode(name: name, path: path, mtime: nil)
        }
        switch entry.kind {
        case .dir:
            return MutableNode(name: name, path: path, mtime: entry.mtime)
        case .file:
            return MutableNode.leaf(
                name: name, path: path, kind: .file,
                size: entry.size, mtime: entry.mtime
            )
        case .symlink:
            return MutableNode.leaf(
                name: name, path: path, kind: .symlink,
                size: entry.size, mtime: entry.mtime
            )
        }
    }
}

/// Mutable counterpart to `TreeNode` used during construction. Freezes to
/// an immutable `TreeNode` with deterministic child order (dirs first,
/// then files/symlinks, each group `localizedStandardCompare`-sorted).
///
/// `kind` is `let`: directories are always created as `.directory`, and
/// leaves never reappear as parents — promotion is impossible by
/// construction. Only `mtime` may be updated, when an explicit `foo/`
/// entry arrives after `foo/x` was already seen.
private final class MutableNode {
    let name: String
    let path: String
    let kind: TreeNode.Kind
    let size: UInt64?
    var mtime: Date?
    private(set) var children: [String: MutableNode] = [:]

    /// Directory constructor (intermediate or explicit).
    init(name: String, path: String, mtime: Date?) {
        self.name = name
        self.path = path
        self.kind = .directory
        self.size = nil
        self.mtime = mtime
    }

    /// Leaf constructor (file or symlink).
    static func leaf(
        name: String, path: String, kind: TreeNode.Kind, size: UInt64, mtime: Date?
    ) -> MutableNode {
        let node = MutableNode(name: name, path: path, kind: kind, size: size, mtime: mtime)
        return node
    }

    private init(name: String, path: String, kind: TreeNode.Kind, size: UInt64, mtime: Date?) {
        self.name = name
        self.path = path
        self.kind = kind
        self.size = size
        self.mtime = mtime
    }

    func addChild(_ node: MutableNode) {
        children[node.name] = node
    }

    func freeze() -> TreeNode {
        let sorted = children.values.sorted { a, b in
            let aIsDir = a.kind == .directory
            let bIsDir = b.kind == .directory
            if aIsDir != bIsDir { return aIsDir }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        return TreeNode(
            name: name, path: path, kind: kind,
            size: size, mtime: mtime,
            children: sorted.map { $0.freeze() }
        )
    }
}
