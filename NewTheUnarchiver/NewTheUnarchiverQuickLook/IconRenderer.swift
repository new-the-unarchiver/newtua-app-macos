import AppKit
import Foundation
import UniformTypeIdentifiers

/// Extension-only side-effect layer: turns a list of `IconCatalog` cids
/// into PNG bytes via `NSWorkspace`, ready to be attached to a
/// `QLPreviewReply` so the rendered HTML can reference them by
/// `cid:`-scheme.
///
/// Cached locally within one `renderPNGs` call — `providePreview` runs
/// once per preview in a fresh process, so a cross-call cache buys
/// nothing. Within a single call, an archive with many entries of the
/// same extension still hits the cache after the first PNG encode.
enum IconRenderer {

    /// Render PNG data for each cid. Returns a sparse dictionary —
    /// cids whose icon couldn't be encoded are simply absent, and the
    /// HTML will render a broken `<img>` placeholder (acceptable
    /// graceful degradation).
    static func renderPNGs(for cids: [String], size: CGFloat = 32) -> [String: Data] {
        var out: [String: Data] = [:]
        for cid in cids where out[cid] == nil {
            if let data = pngData(for: cid, size: size) {
                out[cid] = data
            }
        }
        return out
    }

    private static func pngData(for cid: String, size: CGFloat) -> Data? {
        let utType = IconCatalog.utType(forCID: cid)
        let image = NSWorkspace.shared.icon(for: utType)
        let target = NSSize(width: size, height: size)
        let resized = NSImage(size: target)
        resized.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: target),
            from: .zero,
            operation: .copy,
            fraction: 1.0
        )
        resized.unlockFocus()
        guard let tiff = resized.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else { return nil }
        return png
    }
}
