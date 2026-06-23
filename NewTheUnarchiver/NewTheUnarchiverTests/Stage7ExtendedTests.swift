import Foundation
import Testing
import UniformTypeIdentifiers
@testable import NewTheUnarchiver

@MainActor
@Suite("Stage 7 — Preferences: Archive Formats tab (extended)")
struct Stage7ExtendedTests {

    // MARK: - SupportedFormats invariants

    @Test("Format extensions are unique across the registry")
    func formats_extensionsAreUnique() {
        let all = SupportedFormats.formats.flatMap(\.extensions)
        let unique = Set(all)
        #expect(all.count == unique.count, "duplicate extension in registry: \(all)")
    }

    @Test("Format extensions are lower-case (matches how macOS reports them)")
    func formats_extensionsAreLowercase() {
        for fmt in SupportedFormats.formats {
            for ext in fmt.extensions {
                #expect(ext == ext.lowercased(), "extension \(ext) must be lowercase")
            }
        }
    }

    @Test("Format displayNameKey derives from the first extension")
    func formats_displayNameKey_pattern() {
        for fmt in SupportedFormats.formats {
            #expect(fmt.displayNameKey == "format.\(fmt.extensions[0]).name")
        }
    }

    @Test("Resolved utTypes is non-empty (every entry resolves on this macOS)")
    func formats_utTypes_areResolvable() {
        #expect(!SupportedFormats.utTypes.isEmpty)
        #expect(SupportedFormats.utTypes.count == SupportedFormats.formats.count)
    }

    // MARK: - Stub service edge

    @Test("Stub service returns nil for an unknown UTI")
    func stubService_unknownUTI_isNil() {
        let service = StubFileAssociationsService(initial: [:])
        #expect(service.defaultHandler(forUTI: "no.such.uti") == nil)
    }

    // MARK: - Model: idempotency and error paths

    @Test("Model: calling setAsDefaultForAll twice is idempotent")
    func model_setAsDefaultForAll_idempotent() throws {
        let service = StubFileAssociationsService(initial: [:])
        let model = ArchiveFormatsModel(service: service, ourBundleID: "com.example.us")
        try model.setAsDefaultForAll()
        try model.setAsDefaultForAll()
        #expect(model.allAreUs)
    }

    @Test("Model: empty service produces rows with nil handler and isOurApp == false")
    func model_emptyService_allRowsAreUnowned() {
        let service = StubFileAssociationsService(initial: [:])
        let model = ArchiveFormatsModel(service: service, ourBundleID: "com.example.us")
        #expect(model.rows.count == SupportedFormats.formats.count)
        for row in model.rows {
            #expect(row.currentHandler == nil)
            #expect(row.isOurApp == false)
        }
        #expect(!model.allAreUs)
    }

    @Test("Model: setAsDefault for a single UTI rethrows the service error and rerefreshes")
    func model_setAsDefault_rethrowsAndRefreshes() {
        let service = StubFileAssociationsService(initial: [
            "public.zip-archive": "com.apple.Archive"
        ])
        let model = ArchiveFormatsModel(service: service, ourBundleID: "com.example.us")
        service.shouldThrowOnSet = true
        #expect(throws: StubFileAssociationsService.Boom.self) {
            try model.setAsDefault(forUTI: "public.zip-archive")
        }
        // After throw, model reflects whatever the service currently reports.
        let zip = model.rows.first { $0.format.utiIdentifier == "public.zip-archive" }
        #expect(zip?.currentHandler == "com.apple.Archive")
    }

    @Test("Model: rows preserve registry order")
    func model_rowsPreserveRegistryOrder() {
        let service = StubFileAssociationsService(initial: [:])
        let model = ArchiveFormatsModel(service: service, ourBundleID: "com.example.us")
        let registryUTIs = SupportedFormats.formats.map(\.utiIdentifier)
        let rowUTIs = model.rows.map(\.format.utiIdentifier)
        #expect(registryUTIs == rowUTIs)
    }

    // MARK: - LaunchServicesFileAssociations smoke

    @Test("LaunchServices adapter returns the system's current ZIP handler (string or nil)")
    func launchServices_zipHandler_smoke() {
        let adapter = LaunchServicesFileAssociations()
        // We don't assert a specific bundle ID — different machines have
        // different defaults. The test guards against the adapter crashing or
        // mis-bridging the CFString return value.
        let handler = adapter.defaultHandler(forUTI: "public.zip-archive")
        if let handler { #expect(!handler.isEmpty) }
    }
}

// Stub merged into `TestSupport.swift` as `StubFileAssociationsService` with
// `shouldThrowOnSet` toggle.
