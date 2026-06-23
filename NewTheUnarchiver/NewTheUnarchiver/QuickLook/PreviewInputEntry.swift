import Foundation

/// Engine-agnostic input to `ArchiveTreeBuilder` and `HTMLPreviewRenderer`.
///
/// Why not consume `Newtua.Entry` directly:
/// - `Newtua.Entry` has no public initializer, so unit tests would have to
///   open real archives just to construct one — clashes with the
///   pure-function nature of this layer.
/// - `Newtua.Entry.mtime` is `Int64?` (Unix seconds); the renderer formats
///   it via `DateFormatter`. Converting to `Date` at the boundary keeps
///   the boundary thin and removes that knowledge from the renderer.
/// - `isEncrypted` / `mode` aren't needed for preview — narrower input is
///   easier to reason about.
struct PreviewInputEntry: Equatable, Sendable {
    enum Kind: Sendable, Equatable {
        case file
        case dir
        case symlink
    }

    let path: String
    let kind: Kind
    let size: UInt64
    let mtime: Date?
}
