import AppKit
import Foundation

/// Side-effects that run after a job successfully finishes, gated by
/// `ExtractionOptions.openFolderAfter` / `.moveToTrashAfter`. Behind a
/// protocol so tests can verify the calls without touching Finder / Trash.
@MainActor
protocol PostExtractActions: AnyObject {
    /// Open `url` (the extracted folder) in Finder.
    func openFolder(_ url: URL)

    /// Move `url` (the original archive) to the user's Trash. Best-effort —
    /// `NSWorkspace.recycle` reports failure via completion handler but we
    /// don't surface it; a read-only volume or vanished archive isn't a
    /// crashing error.
    func moveToTrash(_ url: URL)
}

@MainActor
final class SystemPostExtractActions: PostExtractActions {
    func openFolder(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func moveToTrash(_ url: URL) {
        NSWorkspace.shared.recycle([url], completionHandler: nil)
    }
}
