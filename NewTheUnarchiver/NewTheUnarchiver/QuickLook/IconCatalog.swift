import Foundation
import UniformTypeIdentifiers

/// Stable mapping from a tree node to the cid that the HTML preview will
/// reference in `<img src="cid:...">`. The renderer is pure and never
/// touches `NSWorkspace` — the extension target renders the actual PNG
/// once per unique cid and attaches it via `QLPreviewReplyAttachment`.
///
/// Bucketing rules (keeps the attachment count to "extensions in this
/// archive" rather than "entries in this archive"):
/// - all directories share `folderCID`,
/// - all symlinks share `symlinkCID`,
/// - files share a cid keyed by lowercased extension (`icon-ext-png`),
/// - extensionless files share `genericFileCID`.
enum IconCatalog {
    static let folderCID = "icon-folder"
    static let symlinkCID = "icon-symlink"
    static let genericFileCID = "icon-file"

    static func cid(for node: TreeNode) -> String {
        switch node.kind {
        case .directory: return folderCID
        case .symlink: return symlinkCID
        case .file:
            let ext = URL(filePath: node.name).pathExtension.lowercased()
            return ext.isEmpty ? genericFileCID : "icon-ext-\(ext)"
        }
    }

    /// All distinct cids reachable from `tree` — what the extension needs
    /// to pre-render and attach. Insertion order is preserved for
    /// deterministic test fixtures.
    static func uniqueCIDs(in tree: [TreeNode]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        tree.walk { node in
            let id = cid(for: node)
            if seen.insert(id).inserted { ordered.append(id) }
        }
        return ordered
    }

    /// Resolve the `UTType` whose system icon should be rendered for a
    /// given cid. Pure helper — the extension target wraps `NSWorkspace`
    /// around it. Unknown / unresolvable extensions fall back to
    /// `UTType.data` so the renderer never returns `nil`.
    static func utType(forCID cid: String) -> UTType {
        switch cid {
        case folderCID: return .folder
        case symlinkCID: return .symbolicLink
        case genericFileCID: return .data
        default:
            let prefix = "icon-ext-"
            if cid.hasPrefix(prefix) {
                let ext = String(cid.dropFirst(prefix.count))
                return UTType(filenameExtension: ext) ?? .data
            }
            return .data
        }
    }
}
