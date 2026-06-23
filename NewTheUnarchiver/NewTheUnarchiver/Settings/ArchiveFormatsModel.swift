import AppKit
import Foundation
import Observation

/// Icon + display name for whichever app currently owns a UTI. Resolved
/// once per row during `ArchiveFormatsModel.refresh()` so the view never
/// reaches into `NSWorkspace` from inside `body`.
@MainActor
struct HandlerDisplay {
    let icon: NSImage
    let name: String

    static func resolve(bundleID: String) -> HandlerDisplay? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return HandlerDisplay(
            icon: NSWorkspace.shared.icon(forFile: url.path),
            name: FileManager.default.displayName(atPath: url.path)
        )
    }
}

/// View model for the Archive Formats Preferences tab. Holds a row per
/// supported format with the bundle ID of its current default handler (and
/// a resolved icon/name for that handler), and exposes mutations (set one /
/// set all) that go through `FileAssociationsService`. No persistence —
/// Launch Services is the source of truth; we just observe and write.
@MainActor
@Observable
final class ArchiveFormatsModel {
    /// One row in the Archive Formats list. Not `Equatable` — `NSImage`
    /// inside `HandlerDisplay` isn't equatable; tests check fields directly.
    struct Row: Identifiable {
        let format: SupportedFormats.Format
        let currentHandler: String?
        let isOurApp: Bool
        let handlerDisplay: HandlerDisplay?

        var id: String { format.utiIdentifier }
    }

    private(set) var rows: [Row] = []
    private let service: FileAssociationsService
    private let ourBundleID: String

    var allAreUs: Bool { rows.allSatisfy(\.isOurApp) }

    init(service: FileAssociationsService, ourBundleID: String) {
        self.service = service
        self.ourBundleID = ourBundleID
        refresh()
    }

    /// Re-read every row's current handler from Launch Services. Cheap (one
    /// CFString lookup per format + at most one NSWorkspace lookup per
    /// non-us handler). Called on init, after every mutation, and from the
    /// manual "Refresh" button.
    func refresh() {
        rows = SupportedFormats.formats.map { format in
            let handler = service.defaultHandler(forUTI: format.utiIdentifier)
            let isOurs = handler == ourBundleID
            let display = (handler != nil && !isOurs) ? HandlerDisplay.resolve(bundleID: handler!) : nil
            return Row(
                format: format,
                currentHandler: handler,
                isOurApp: isOurs,
                handlerDisplay: display
            )
        }
    }

    /// Make us the default for a single UTI. Throws if Launch Services
    /// refuses. `defer` keeps the row snapshot honest even when the call
    /// throws — Launch Services may have partially applied the change.
    func setAsDefault(forUTI uti: String) throws {
        defer { refresh() }
        try service.setDefaultHandler(ourBundleID, forUTI: uti)
    }

    /// Bulk: make us the default for every supported format. The first
    /// failure aborts and rethrows; rows that succeeded before the failure
    /// stay set on the OS side and the model picks that up via `defer`-ed
    /// refresh. Launch Services has no transactional contract.
    func setAsDefaultForAll() throws {
        defer { refresh() }
        for format in SupportedFormats.formats {
            try service.setDefaultHandler(ourBundleID, forUTI: format.utiIdentifier)
        }
    }
}
