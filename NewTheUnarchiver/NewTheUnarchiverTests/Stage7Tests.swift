import Foundation
import Testing
@testable import NewTheUnarchiver

@MainActor
@Suite("Stage 7 — Preferences: Archive Formats tab (TDD-min)")
struct Stage7Tests {

    // MARK: - SupportedFormats: rich registry

    @Test("Formats registry covers the Phase 5 set, with UTI identifier and at least one extension")
    func formats_coversPhase5Set() {
        let utis = Set(SupportedFormats.formats.map(\.utiIdentifier))
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
            #expect(utis.contains(uti), "SupportedFormats.formats is missing \(uti)")
        }
        #expect(SupportedFormats.formats.count == 23)
        for fmt in SupportedFormats.formats {
            #expect(!fmt.extensions.isEmpty, "format \(fmt.utiIdentifier) must list at least one extension")
        }
    }

    @Test("Derived fileExtensions stays consistent with the rich registry")
    func formats_extensionsAreDerived() {
        let derived = Set(SupportedFormats.fileExtensions)
        let flattened = Set(SupportedFormats.formats.flatMap(\.extensions))
        #expect(derived == flattened)
    }

    // MARK: - FileAssociationsService stub round-trip

    @Test("Stub service: set then get round-trips the bundle ID")
    func stubService_setThenGet_roundtrips() throws {
        let service = StubFileAssociationsService(initial: [
            "public.zip-archive": "com.apple.Archive"
        ])
        #expect(service.defaultHandler(forUTI: "public.zip-archive") == "com.apple.Archive")
        try service.setDefaultHandler("com.example.us", forUTI: "public.zip-archive")
        #expect(service.defaultHandler(forUTI: "public.zip-archive") == "com.example.us")
    }

    // MARK: - ArchiveFormatsModel

    @Test("Model: initial load reads current handler per UTI and flags ours")
    func model_initialLoad_readsCurrentHandler() throws {
        let initial: [String: String] = [
            "public.zip-archive": "com.apple.Archive",
            "org.7-zip.7-zip-archive": "com.example.us",
        ]
        let service = StubFileAssociationsService(initial: initial)
        let model = ArchiveFormatsModel(service: service, ourBundleID: "com.example.us")
        let zip = try #require(model.rows.first { $0.format.utiIdentifier == "public.zip-archive" })
        #expect(zip.currentHandler == "com.apple.Archive")
        #expect(zip.isOurApp == false)
        let sevenZ = try #require(model.rows.first { $0.format.utiIdentifier == "org.7-zip.7-zip-archive" })
        #expect(sevenZ.isOurApp)
    }

    @Test("Model: setAsDefaultForAll switches every row to us")
    func model_setAsDefaultForAll_switchesAll() throws {
        let service = StubFileAssociationsService(initial: [:])
        let model = ArchiveFormatsModel(service: service, ourBundleID: "com.example.us")
        try model.setAsDefaultForAll()
        #expect(model.allAreUs)
        for row in model.rows {
            #expect(row.currentHandler == "com.example.us")
        }
    }

    @Test("Model: setAsDefault changes one row, others stay")
    func model_setAsDefault_singleRow() throws {
        let service = StubFileAssociationsService(initial: [
            "public.zip-archive": "com.apple.Archive",
            "org.7-zip.7-zip-archive": "com.example.other",
        ])
        let model = ArchiveFormatsModel(service: service, ourBundleID: "com.example.us")
        try model.setAsDefault(forUTI: "public.zip-archive")
        let zip = try #require(model.rows.first { $0.format.utiIdentifier == "public.zip-archive" })
        #expect(zip.isOurApp)
        let sevenZ = try #require(model.rows.first { $0.format.utiIdentifier == "org.7-zip.7-zip-archive" })
        #expect(!sevenZ.isOurApp)
    }

    @Test("Model: refresh picks up an external Launch Services change")
    func model_refresh_picksUpExternal() throws {
        let service = StubFileAssociationsService(initial: [
            "public.zip-archive": "com.apple.Archive"
        ])
        let model = ArchiveFormatsModel(service: service, ourBundleID: "com.example.us")
        // Simulate Finder → Get Info → Change All while Preferences is open.
        service.externalSet("public.zip-archive", bundleID: "com.example.us")
        let before = try #require(model.rows.first { $0.format.utiIdentifier == "public.zip-archive" })
        #expect(!before.isOurApp, "model snapshot is stale until refresh()")
        model.refresh()
        let after = try #require(model.rows.first { $0.format.utiIdentifier == "public.zip-archive" })
        #expect(after.isOurApp)
    }

    @Test("Model: allAreUs is false if at least one row has another handler")
    func model_allAreUs_falseIfAnyOther() {
        var initial: [String: String] = [:]
        for fmt in SupportedFormats.formats { initial[fmt.utiIdentifier] = "com.example.us" }
        initial["public.zip-archive"] = "com.apple.Archive"
        let service = StubFileAssociationsService(initial: initial)
        let model = ArchiveFormatsModel(service: service, ourBundleID: "com.example.us")
        #expect(!model.allAreUs)
    }
}

// `StubFileAssociationsService` lives in `TestSupport.swift` — shared by all
// Stage 7 test files.
