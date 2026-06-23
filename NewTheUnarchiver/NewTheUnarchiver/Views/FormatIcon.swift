import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Resolves archive file URLs to Finder-style icons. The set of archive
/// extensions is tiny and bounded, so we cache `NSImage` per extension —
/// the row view rebuilds many times during a single extraction and asking
/// `NSWorkspace` each time would burn cycles on a known answer.
enum FormatIcon {
    @MainActor private static var cache: [String: NSImage] = [:]

    @MainActor
    static func image(for url: URL) -> Image {
        Image(nsImage: nsImage(for: url))
    }

    @MainActor
    private static func nsImage(for url: URL) -> NSImage {
        let ext = url.pathExtension.lowercased()
        if let hit = cache[ext] { return hit }
        let image: NSImage
        if let utType = UTType(filenameExtension: ext), utType.conforms(to: .archive) {
            image = NSWorkspace.shared.icon(for: utType)
        } else {
            image = NSWorkspace.shared.icon(for: .archive)
        }
        cache[ext] = image
        return image
    }
}
