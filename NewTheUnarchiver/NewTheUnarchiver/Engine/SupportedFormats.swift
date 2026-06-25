import Foundation
import UniformTypeIdentifiers

/// Single source of truth for which archive formats the app advertises to the
/// system. Used by `File ▸ Open…`'s filter, the `Info.plist`
/// `CFBundleDocumentTypes` declaration, and the Archive Formats Preferences
/// tab — so the three never drift.
///
/// Matches the engine's Phase 5 format set (see `docs/phase5-formats-priority.md`).
/// Formats without a stable system UTI (`ar`, `msi`) use app-declared imported
/// types in `Info.plist` → `UTImportedTypeDeclarations`.
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

    /// Custom UTIs declared in `Info.plist` → `UTImportedTypeDeclarations`.
    enum ImportedUTI {
        static let unixAr = "aleksei.trankov.newtheunarchiver.unix-ar-archive"
        static let msi = "aleksei.trankov.newtheunarchiver.msi-installer"
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
        Format(utiIdentifier: "com.facebook.zstandard-archive", extensions: ["zst", "tar.zst"]),
        Format(utiIdentifier: "org.tukaani.lzma-archive", extensions: ["lzma", "tar.lzma"]),
        Format(utiIdentifier: "public.z-archive", extensions: ["z", "tar.z"]),
        Format(utiIdentifier: "com.winzip.zipx-archive", extensions: ["zipx"]),
        Format(utiIdentifier: "com.microsoft.cab", extensions: ["cab"]),
        Format(utiIdentifier: "org.debian.deb-archive", extensions: ["deb", "udeb"]),
        Format(utiIdentifier: "com.redhat.rpm-archive", extensions: ["rpm"]),
        Format(utiIdentifier: "public.cpio-archive", extensions: ["cpio"]),
        Format(utiIdentifier: "com.apple.xar-archive", extensions: ["xar"]),
        Format(utiIdentifier: "com.apple.installer-package-archive", extensions: ["pkg"]),
        Format(utiIdentifier: ImportedUTI.unixAr, extensions: ["ar"]),
        Format(utiIdentifier: ImportedUTI.msi, extensions: ["msi"]),
        Format(utiIdentifier: "public.iso-image", extensions: ["iso"]),
        Format(utiIdentifier: "org.archive.warc-archive", extensions: ["warc"]),
        Format(utiIdentifier: "com.microsoft.windows-executable", extensions: ["exe"]),
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
