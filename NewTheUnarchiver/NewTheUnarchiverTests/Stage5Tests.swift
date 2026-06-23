import Foundation
import Testing
import UniformTypeIdentifiers
@testable import NewTheUnarchiver

@MainActor
@Suite("Stage 5 — open scenarios (TDD minimum)")
struct Stage5Tests {

    // MARK: - SupportedFormats canonical set

    @Test("SupportedFormats declares the v1 popular-archive extension set")
    func supportedFormats_v1Extensions() {
        let exts = SupportedFormats.fileExtensions
        let required = ["zip", "7z", "rar", "tar", "gz", "bz2", "xz", "tar.gz", "tar.bz2", "tar.xz"]
        for ext in required {
            #expect(exts.contains(ext), "SupportedFormats.fileExtensions is missing \(ext)")
        }
    }

    @Test("SupportedFormats.utTypes covers the common archive UTIs by identifier")
    func supportedFormats_utTypesCoverArchiveUTIs() {
        let identifiers = Set(SupportedFormats.utTypes.map(\.identifier))
        #expect(identifiers.contains("public.zip-archive"))
        #expect(identifiers.contains("org.7-zip.7-zip-archive"))
        #expect(identifiers.contains("com.rarlab.rar-archive"))
        #expect(identifiers.contains("public.tar-archive"))
        #expect(identifiers.contains("org.gnu.gnu-zip-archive"))
        #expect(identifiers.contains("public.bzip2-archive"))
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
