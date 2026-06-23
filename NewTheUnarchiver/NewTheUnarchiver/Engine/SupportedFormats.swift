import Foundation
import UniformTypeIdentifiers

/// Single source of truth for which archive formats v1 advertises to the
/// system. Used by `File ▸ Open…`'s filter, the `Info.plist`
/// `CFBundleDocumentTypes` declaration, and the Archive Formats Preferences
/// tab — so the three never drift.
///
/// The engine opens more formats than this list; we restrict the OS-level
/// advertisement to the "popular" set from `docs/Supported formats.md`. Less
/// noise in Finder's "Open With" menu, fewer accidental opens of files the
/// engine cannot extract cleanly.
enum SupportedFormats {
    /// Rich metadata per format. The UTI identifier feeds Launch Services
    /// (`LSCopyDefaultRoleHandlerForContentType`); `extensions` lists trailing
    /// filename components users will recognize.
    struct Format: Sendable, Identifiable, Equatable {
        let utiIdentifier: String
        let extensions: [String]

        var id: String { utiIdentifier }

        /// Localizable key for the human-readable format name (e.g. "ZIP
        /// archive"). Derived from the first extension so the localization
        /// catalog stays in lockstep with the registry without a second
        /// per-format declaration.
        var displayNameKey: String { "format.\(extensions[0]).name" }
    }

    /// Order here is the order shown in the Preferences tab.
    static let formats: [Format] = [
        Format(utiIdentifier: "public.zip-archive", extensions: ["zip"]),
        Format(utiIdentifier: "org.7-zip.7-zip-archive", extensions: ["7z"]),
        Format(utiIdentifier: "com.rarlab.rar-archive", extensions: ["rar"]),
        Format(utiIdentifier: "public.tar-archive", extensions: ["tar"]),
        Format(utiIdentifier: "org.gnu.gnu-zip-archive", extensions: ["gz", "tar.gz"]),
        Format(utiIdentifier: "public.bzip2-archive", extensions: ["bz2", "tar.bz2"]),
        Format(utiIdentifier: "org.tukaani.xz-archive", extensions: ["xz", "tar.xz"]),
    ]

    /// Flat list of trailing extensions for `Info.plist` sync. Materialized
    /// once at startup — `formats` itself is static-let.
    static let fileExtensions: [String] = formats.flatMap(\.extensions)

    /// UTTypes for the SwiftUI `fileImporter`'s `allowedContentTypes`.
    /// Resolved by identifier (not by static `UTType` members) because not
    /// every archive type has a stable static property across macOS SDKs.
    /// Any identifier the runtime can't resolve is silently dropped — better
    /// to lose one format from the open panel than to crash on launch.
    static let utTypes: [UTType] = formats.compactMap { UTType($0.utiIdentifier) }
}
