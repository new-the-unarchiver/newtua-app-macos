import Foundation
import Testing
import UniformTypeIdentifiers
@testable import NewTheUnarchiver

@MainActor
@Suite("Stage 5 — open scenarios (TDD minimum)")
struct Stage5Tests {

    // MARK: - SupportedFormats canonical set

    @Test("SupportedFormats declares the Phase 5 archive extension set")
    func supportedFormats_phase5Extensions() {
        let exts = SupportedFormats.fileExtensions
        let required = [
            "zip", "7z", "rar", "tar", "gz", "bz2", "xz",
            "tar.gz", "tar.bz2", "tar.xz",
            "zst", "tar.zst", "lzma", "tar.lzma", "z", "tar.z",
            "lz4", "tar.lz4", "br", "tar.br",
            "zipx", "cab", "deb", "udeb", "rpm", "cpio", "xar", "pkg",
            "ar", "msi", "iso", "warc", "exe",
            // Classic Mac — The Unarchiver's heritage.
            "sit", "sitx", "hqx", "bin", "as", "cpt", "pit",
            // Retro DOS / CP-M / Amiga.
            "arj", "zoo", "lbr", "arc", "ark", "pak", "spark",
            "sq", "qqq", "alz", "lzx", "pp", "dms",
            // Filesystem and disk images.
            "squashfs", "sfs", "appimage", "wim", "esd", "swm",
            "hfs", "hfsplus", "hfsx", "dmg",
            // Zip-based containers and documents.
            "jar", "apk", "ipa", "crx", "conda",
            "epub", "docx", "xlsx", "pptx", "odt", "ods", "odp",
        ]
        for ext in required {
            #expect(exts.contains(ext), "SupportedFormats.fileExtensions is missing \(ext)")
        }
        #expect(SupportedFormats.formats.count == 57)
    }

    @Test("SupportedFormats.utTypes covers the Phase 5 archive UTIs by identifier")
    func supportedFormats_utTypesCoverArchiveUTIs() {
        let identifiers = Set(SupportedFormats.utTypes.map(\.identifier))
        let required = [
            "public.zip-archive",
            "org.7-zip.7-zip-archive",
            "com.rarlab.rar-archive",
            "public.tar-archive",
            "org.gnu.gnu-zip-archive",
            "public.bzip2-archive",
            "org.tukaani.xz-archive",
            "com.facebook.zstandard-archive",
            "org.tukaani.lzma-archive",
            "public.z-archive",
            "public.lz4-archive",
            "com.winzip.zipx-archive",
            "com.microsoft.cab",
            "org.debian.deb-archive",
            "com.redhat.rpm-archive",
            "public.cpio-archive",
            "com.apple.xar-archive",
            "com.apple.installer-package-archive",
            SupportedFormats.ImportedUTI.unixAr,
            SupportedFormats.ImportedUTI.msi,
            "public.iso-image",
            "org.archive.warc-archive",
            "com.microsoft.windows-executable",
        ]
        for uti in required {
            #expect(identifiers.contains(uti), "SupportedFormats.utTypes is missing \(uti)")
        }
    }

    @Test("Every single-component file extension resolves to a real UTType")
    func supportedFormats_extensionsResolveToUTType() {
        for ext in SupportedFormats.fileExtensions where !ext.contains(".") {
            #expect(UTType(filenameExtension: ext) != nil, "no UTType for \(ext)")
        }
    }

    @Test("SupportedFormats.fileExtensions has no duplicates and is all-lowercase")
    func supportedFormats_normalized() {
        let exts = SupportedFormats.fileExtensions
        #expect(Set(exts).count == exts.count)
        for ext in exts {
            #expect(ext == ext.lowercased(), "\(ext) is not lowercased")
        }
    }

    // MARK: - AppModel.enqueue — Stage 5 boundary

    @Test("AppModel.enqueue ignores non-file URLs (defense for onOpenURLs payloads)")
    func enqueue_ignoresNonFileURLs() {
        let app = AppModel()
        guard let httpURL = URL(string: "https://example.com/a.zip") else {
            Issue.record("could not construct HTTP URL")
            return
        }
        app.enqueue(urls: [httpURL])
        #expect(app.queue.isEmpty)
    }
}
