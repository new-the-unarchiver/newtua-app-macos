import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Resolves archive file URLs to Finder-style icons. The set of archive
/// extensions is tiny and bounded, so we cache `NSImage` per archive UTI —
/// the row view rebuilds many times during a single extraction and asking
/// `NSWorkspace` each time would burn cycles on a known answer.
enum FormatIcon {
    @MainActor private static var archiveCache: [String: NSImage] = [:]
    @MainActor private static let fallback: NSImage = NSWorkspace.shared.icon(for: .archive)

    @MainActor
    static func image(for url: URL) -> Image {
        let ext = url.pathExtension.lowercased()
        guard let utType = UTType(filenameExtension: ext), utType.conforms(to: .archive) else {
            return Image(nsImage: fallback)
        }
        return Image(nsImage: cachedIcon(for: utType, key: ext))
    }

    @MainActor
    static func image(forUTI identifier: String) -> Image {
        guard let utType = UTType(identifier), utType.conforms(to: .archive) else {
            return Image(nsImage: fallback)
        }
        let key = utType.preferredFilenameExtension ?? utType.identifier
        return Image(nsImage: cachedIcon(for: utType, key: key))
    }

    @MainActor
    private static func cachedIcon(for utType: UTType, key: String) -> NSImage {
        if let hit = archiveCache[key] { return hit }
        let icon = NSWorkspace.shared.icon(for: utType)
        archiveCache[key] = icon
        return icon
    }
}
