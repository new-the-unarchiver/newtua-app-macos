import Foundation
import Testing
@testable import NewTheUnarchiver

@MainActor
@Suite("Stage 7 — Preferences: Extraction tab")
struct Stage7Tab2Tests {

    // MARK: - ExtractionOptions: Codable + defaults

    @Test("ExtractionOptions: Codable round-trip preserves all fields")
    func extractionOptions_codable_roundtrip() throws {
        let original = ExtractionOptions(
            wrapperMode: .always,
            destinationStrategy: .fixed(URL(fileURLWithPath: "/tmp/out")),
            openFolderAfter: true,
            moveToTrashAfter: true,
            defaultEncoding: "shift_jis"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ExtractionOptions.self, from: data)
        #expect(decoded == original)
    }

    @Test("ExtractionOptions: defaults match the original The Unarchiver")
    func extractionOptions_defaults_matchOriginal() {
        let options = ExtractionOptions()
        #expect(options.wrapperMode == .onlyIfMultiple)
        #expect(options.destinationStrategy == .nextToArchive)
        #expect(options.openFolderAfter == false)
        #expect(options.moveToTrashAfter == false)
        #expect(options.defaultEncoding == nil)
    }

    @Test("DestinationStrategy.fixed(URL) survives Codable round-trip")
    func destinationStrategy_fixed_codable() throws {
        let strategy: DestinationStrategy = .fixed(URL(fileURLWithPath: "/Users/x/Downloads"))
        let data = try JSONEncoder().encode(strategy)
        let decoded = try JSONDecoder().decode(DestinationStrategy.self, from: data)
        #expect(decoded == strategy)
    }

    // MARK: - AppModel persistence

    @Test("AppModel: mutation persists to UserDefaults")
    func appModel_persists_onMutation() throws {
        let iso = TestSupport.isolatedDefaults()
        defer { iso.teardown() }
        let defaults = iso.defaults
        let model = AppModel(defaults: defaults)
        model.extractionOptions.openFolderAfter = true
        let stored = try #require(defaults.data(forKey: AppModel.extractionOptionsKey))
        let decoded = try JSONDecoder().decode(ExtractionOptions.self, from: stored)
        #expect(decoded.openFolderAfter == true)
    }

    @Test("AppModel: init reads persisted ExtractionOptions from UserDefaults")
    func appModel_loadsPersisted_onInit() throws {
        let iso = TestSupport.isolatedDefaults()
        defer { iso.teardown() }
        let defaults = iso.defaults
        let written = ExtractionOptions(
            wrapperMode: .always,
            destinationStrategy: .askEachTime,
            openFolderAfter: true,
            moveToTrashAfter: true,
            defaultEncoding: "cp1251"
        )
        defaults.set(try JSONEncoder().encode(written), forKey: AppModel.extractionOptionsKey)

        let model = AppModel(defaults: defaults)
        #expect(model.extractionOptions == written)
    }

    @Test("AppModel: corrupt UserDefaults payload falls back to defaults, no crash")
    func appModel_corruptDefaults_fallsBack() {
        let iso = TestSupport.isolatedDefaults()
        defer { iso.teardown() }
        let defaults = iso.defaults
        defaults.set(Data([0xFF, 0x00, 0xAB]), forKey: AppModel.extractionOptionsKey)
        let model = AppModel(defaults: defaults)
        #expect(model.extractionOptions == ExtractionOptions())
    }

    @Test("AppModel: identity write to extractionOptions does not re-encode")
    func appModel_identityWrite_isANoOp() throws {
        let iso = TestSupport.isolatedDefaults()
        defer { iso.teardown() }
        let defaults = iso.defaults
        let model = AppModel(defaults: defaults)
        // No stored value yet → nothing was persisted by init.
        #expect(defaults.data(forKey: AppModel.extractionOptionsKey) == nil)
        // Re-assign the same value — must not start persisting either.
        model.extractionOptions = model.extractionOptions
        #expect(defaults.data(forKey: AppModel.extractionOptionsKey) == nil)
    }
}
