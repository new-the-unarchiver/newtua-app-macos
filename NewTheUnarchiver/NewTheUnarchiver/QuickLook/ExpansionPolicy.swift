import Foundation

/// Decides which directory nodes open by default in the rendered HTML
/// preview. Root level is always laid out fully; nested directories are
/// auto-expanded only when small enough to scan at a glance.
struct ExpansionPolicy: Sendable, Equatable {
    let rootAlwaysExpanded: Bool
    let maxChildrenForAutoExpand: Int

    static let `default` = ExpansionPolicy(
        rootAlwaysExpanded: true,
        maxChildrenForAutoExpand: 5
    )

    func shouldExpand(_ node: TreeNode, isRoot: Bool) -> Bool {
        if isRoot { return rootAlwaysExpanded }
        return node.children.count <= maxChildrenForAutoExpand
    }
}
