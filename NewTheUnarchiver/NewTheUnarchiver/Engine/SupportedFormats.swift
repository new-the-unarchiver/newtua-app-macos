import Foundation
import UniformTypeIdentifiers

/// Single source of truth for which archive formats v1 advertises to the
/// system. Used by the `File ▸ Open…` panel filter and (separately) by the
/// `Info.plist` `CFBundleDocumentTypes` declaration so the two never drift.
///
/// The engine opens more formats than this list; we restrict the OS-level
/// advertisement to the "popular" set from `docs/Supported formats.md`. Less
/// noise in the Finder's "Open With" menu, fewer accidental opens of files
/// the engine cannot extract cleanly.
enum SupportedFormats {
    /// Lower-case extensions, single- and compound-form. The system matches
    /// only the trailing component (`gz`, `bz2`, `xz`); compound entries
    /// like `tar.gz` are kept for documentation.
    static let fileExtensions: [String] = [
        "zip",
        "7z",
        "rar",
        "tar",
        "gz",
        "bz2",
        "xz",
        "tar.gz",
        "tar.bz2",
        "tar.xz",
    ]

    /// UTTypes for the SwiftUI `fileImporter`'s `allowedContentTypes`.
    ///
    /// We resolve them by identifier (not by static `UTType` members) because
    /// not every archive type has a stable static property across macOS SDKs.
    /// Any identifier the runtime can't resolve is silently dropped — better
    /// to lose one format from the open panel than to crash on launch.
    static let utTypes: [UTType] = [
        "public.zip-archive",
        "org.7-zip.7-zip-archive",
        "com.rarlab.rar-archive",
        "public.tar-archive",
        "org.gnu.gnu-zip-archive",
        "public.bzip2-archive",
        "org.tukaani.xz-archive",
    ].compactMap { UTType($0) }
}
