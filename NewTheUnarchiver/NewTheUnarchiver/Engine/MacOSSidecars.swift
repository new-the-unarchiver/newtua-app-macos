import Foundation

/// macOS-sidecar path components the newtua engine silently drops on
/// extraction. Centralised so the queue's `topLevelItemCount` and the
/// QuickLook tree builder stay in lockstep with what actually lands on
/// disk — if the engine's drop-list ever widens, only this file changes.
///
/// Case-sensitive by engine contract: archives can carry whatever bytes
/// they want, and we match exactly what the engine matches so the count
/// and the rendered preview don't drift from reality.
nonisolated enum MacOSSidecars {
    static func matches(_ component: String) -> Bool {
        component == "__MACOSX"
            || component == ".DS_Store"
            || component.hasPrefix("._")
    }

    static func matches(_ component: Substring) -> Bool {
        component == "__MACOSX"
            || component == ".DS_Store"
            || component.hasPrefix("._")
    }
}
