import Foundation
import UniformTypeIdentifiers

/// Single source of truth for which archive formats the app advertises to the
/// system. Used by `File ▸ Open…`'s filter, the `Info.plist`
/// `CFBundleDocumentTypes` declaration, the Quick Look extension's
/// `QLSupportedContentTypes`, and the Archive Formats Preferences tab — so the
/// four never drift.
///
/// Covers the full format set of the engine behind `Newtua`. Formats macOS has
/// no built-in type for are declared by the app itself in `Info.plist` →
/// `UTImportedTypeDeclarations` (see `ImportedUTI`).
enum SupportedFormats {
    /// How hard the app competes to open a type, mirrored into `Info.plist`'s
    /// `LSHandlerRank`.
    enum HandlerRank: String, Sendable {
        /// Ordinary archives: the app offers itself as the default handler.
        case standard = "Default"
        /// Types that belong to another app (documents, Apple disk images):
        /// we appear under "Open With" but never take the default away from
        /// Word, Books or DiskImageMounter.
        case alternate = "Alternate"
    }

    /// Rich metadata per format. The UTI identifier feeds Launch Services
    /// (`LSCopyDefaultRoleHandlerForContentType`); `extensions` lists trailing
    /// filename components users will recognize.
    struct Format: Sendable, Identifiable, Equatable {
        let utiIdentifier: String
        let extensions: [String]
        let rank: HandlerRank

        init(utiIdentifier: String, extensions: [String], rank: HandlerRank = .standard) {
            self.utiIdentifier = utiIdentifier
            self.extensions = extensions
            self.rank = rank
        }

        var id: String { utiIdentifier }

        /// Localizable key for the human-readable format name (e.g. "ZIP
        /// archive"). Derived from the first extension so the localization
        /// catalog stays in lockstep with the registry without a second
        /// per-format declaration.
        var displayNameKey: String { "format.\(extensions[0]).name" }
    }

    /// UTIs the app declares itself in `Info.plist` →
    /// `UTImportedTypeDeclarations`, because macOS ships no type for them.
    ///
    /// Two kinds live here. Most are our own reverse-DNS types. Three —
    /// `deb`, `rpm`, `warc` — keep the identifier the wider world already uses,
    /// since those belong to Debian, Red Hat and the Internet Archive; macOS
    /// simply doesn't ship them, so we declare what we know rather than mint a
    /// competing name. (They looked resolvable for a long time only because a
    /// stale Launch Services record supplied them; rebuilding the database
    /// exposed that.)
    enum ImportedUTI {
        static let deb = "org.debian.deb-archive"
        static let rpm = "com.redhat.rpm-archive"
        static let warc = "org.archive.warc-archive"

        static let unixAr = "aleksei.trankov.newtheunarchiver.unix-ar-archive"
        static let msi = "aleksei.trankov.newtheunarchiver.msi-installer"
        static let brotli = "aleksei.trankov.newtheunarchiver.brotli-archive"
        static let compactpro = "aleksei.trankov.newtheunarchiver.compactpro-archive"
        static let packit = "aleksei.trankov.newtheunarchiver.packit-archive"
        static let arj = "aleksei.trankov.newtheunarchiver.arj-archive"
        static let zoo = "aleksei.trankov.newtheunarchiver.zoo-archive"
        static let lbr = "aleksei.trankov.newtheunarchiver.lbr-archive"
        static let arc = "aleksei.trankov.newtheunarchiver.arc-archive"
        static let squeeze = "aleksei.trankov.newtheunarchiver.squeeze-archive"
        static let alz = "aleksei.trankov.newtheunarchiver.alz-archive"
        static let lzx = "aleksei.trankov.newtheunarchiver.lzx-archive"
        static let powerpacker = "aleksei.trankov.newtheunarchiver.powerpacker-archive"
        static let dms = "aleksei.trankov.newtheunarchiver.dms-archive"
        static let squashfs = "aleksei.trankov.newtheunarchiver.squashfs-image"
        static let appimage = "aleksei.trankov.newtheunarchiver.appimage-bundle"
        static let wim = "aleksei.trankov.newtheunarchiver.wim-image"
        static let hfsplus = "aleksei.trankov.newtheunarchiver.hfsplus-image"
        static let android = "aleksei.trankov.newtheunarchiver.android-package"
        static let chrome = "aleksei.trankov.newtheunarchiver.chrome-extension"
        static let conda = "aleksei.trankov.newtheunarchiver.conda-package"
    }

    /// Order here is the order shown in the Preferences tab.
    static let formats: [Format] = [
        // Mainstream archives and packages.
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
        Format(utiIdentifier: "public.lz4-archive", extensions: ["lz4", "tar.lz4"]),
        Format(utiIdentifier: "com.winzip.zipx-archive", extensions: ["zipx"]),
        Format(utiIdentifier: "com.microsoft.cab", extensions: ["cab"]),
        Format(utiIdentifier: ImportedUTI.deb, extensions: ["deb", "udeb"]),
        Format(utiIdentifier: ImportedUTI.rpm, extensions: ["rpm"]),
        Format(utiIdentifier: "public.cpio-archive", extensions: ["cpio"]),
        Format(utiIdentifier: "com.apple.xar-archive", extensions: ["xar"]),
        Format(utiIdentifier: "com.apple.installer-package-archive", extensions: ["pkg"]),
        Format(utiIdentifier: ImportedUTI.unixAr, extensions: ["ar"]),
        Format(utiIdentifier: ImportedUTI.msi, extensions: ["msi"]),
        Format(utiIdentifier: "public.iso-image", extensions: ["iso"]),
        Format(utiIdentifier: ImportedUTI.warc, extensions: ["warc"]),
        Format(utiIdentifier: "com.microsoft.windows-executable", extensions: ["exe"]),

        // Standalone compressors.
        Format(utiIdentifier: ImportedUTI.brotli, extensions: ["br", "tar.br"]),

        // Classic Mac formats — The Unarchiver's heritage.
        Format(utiIdentifier: "com.stuffit.archive.sit", extensions: ["sit"]),
        Format(utiIdentifier: "com.stuffit.archive.sitx", extensions: ["sitx"]),
        Format(utiIdentifier: "com.apple.binhex-archive", extensions: ["hqx"]),
        Format(utiIdentifier: "com.apple.macbinary-archive", extensions: ["bin"], rank: .alternate),
        Format(utiIdentifier: "com.apple.applesingle-archive", extensions: ["as"], rank: .alternate),
        Format(utiIdentifier: ImportedUTI.compactpro, extensions: ["cpt"]),
        Format(utiIdentifier: ImportedUTI.packit, extensions: ["pit"]),

        // Retro DOS / CP-M / Amiga archivers.
        Format(utiIdentifier: ImportedUTI.arj, extensions: ["arj"]),
        Format(utiIdentifier: ImportedUTI.zoo, extensions: ["zoo"]),
        Format(utiIdentifier: ImportedUTI.lbr, extensions: ["lbr"]),
        Format(utiIdentifier: ImportedUTI.arc, extensions: ["arc", "ark", "pak", "spark"]),
        Format(utiIdentifier: ImportedUTI.squeeze, extensions: ["sq", "qqq"]),
        Format(utiIdentifier: ImportedUTI.alz, extensions: ["alz"]),
        Format(utiIdentifier: ImportedUTI.lzx, extensions: ["lzx"]),
        Format(utiIdentifier: ImportedUTI.powerpacker, extensions: ["pp"]),
        Format(utiIdentifier: ImportedUTI.dms, extensions: ["dms"]),

        // Filesystem and disk images.
        Format(utiIdentifier: ImportedUTI.squashfs, extensions: ["squashfs", "sfs"]),
        Format(utiIdentifier: ImportedUTI.appimage, extensions: ["appimage"]),
        Format(utiIdentifier: ImportedUTI.wim, extensions: ["wim", "esd", "swm"]),
        Format(utiIdentifier: ImportedUTI.hfsplus, extensions: ["hfs", "hfsplus", "hfsx"]),
        Format(utiIdentifier: "com.apple.disk-image-udif", extensions: ["dmg"], rank: .alternate),

        // Zip-based containers.
        Format(utiIdentifier: "com.sun.java-archive", extensions: ["jar"]),
        Format(utiIdentifier: ImportedUTI.android, extensions: ["apk"]),
        Format(utiIdentifier: "com.apple.itunes.ipa", extensions: ["ipa"]),
        Format(utiIdentifier: ImportedUTI.chrome, extensions: ["crx"]),
        Format(utiIdentifier: ImportedUTI.conda, extensions: ["conda"]),

        // Documents: offered in "Open With", never claimed as the default.
        Format(utiIdentifier: "org.idpf.epub-container", extensions: ["epub"], rank: .alternate),
        Format(utiIdentifier: "org.openxmlformats.wordprocessingml.document", extensions: ["docx"], rank: .alternate),
        Format(utiIdentifier: "org.openxmlformats.spreadsheetml.sheet", extensions: ["xlsx"], rank: .alternate),
        Format(utiIdentifier: "org.openxmlformats.presentationml.presentation", extensions: ["pptx"], rank: .alternate),
        Format(utiIdentifier: "org.oasis-open.opendocument.text", extensions: ["odt"], rank: .alternate),
        Format(utiIdentifier: "org.oasis-open.opendocument.spreadsheet", extensions: ["ods"], rank: .alternate),
        Format(utiIdentifier: "org.oasis-open.opendocument.presentation", extensions: ["odp"], rank: .alternate),
    ]

    /// Every UTI the app declares itself — must match
    /// `UTImportedTypeDeclarations` in `Info.plist` exactly. A type missing
    /// from here resolves only by luck (another app declaring it, or a stale
    /// Launch Services record) and silently stops working on a clean Mac.
    static let appDeclaredUTIs: Set<String> = Set(
        formats.map(\.utiIdentifier).filter {
            $0.hasPrefix("aleksei.trankov.newtheunarchiver.")
                || $0 == ImportedUTI.deb || $0 == ImportedUTI.rpm || $0 == ImportedUTI.warc
        }
    )

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
