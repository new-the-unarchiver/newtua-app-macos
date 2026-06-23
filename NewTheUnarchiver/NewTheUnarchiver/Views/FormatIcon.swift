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
        Image(nsImage: nsImage(for: url))
    }

    @MainActor
    private static func nsImage(for url: URL) -> NSImage {
        let ext = url.pathExtension.lowercased()
        guard let utType = UTType(filenameExtension: ext), utType.conforms(to: .archive) else {
            return fallback
        }
        if let hit = archiveCache[ext] { return hit }
        let icon = NSWorkspace.shared.icon(for: utType)
        archiveCache[ext] = icon
        return icon
    }
}
