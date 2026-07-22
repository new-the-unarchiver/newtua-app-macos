import Foundation
import Testing
@testable import NewTheUnarchiver

/// `SupportedFormats` is the single source of truth for which types the app
/// advertises, but Launch Services and Quick Look read the two `Info.plist`
/// files instead. Nothing at build time keeps the three in step, so these
/// tests do — a format added to the registry and forgotten in a plist (or the
/// reverse) fails here rather than shipping as a type Finder never offers.
@Suite("Format registry ↔ Info.plist stay in sync")
struct FormatRegistrySyncTests {
    private static func plist(at relativePath: String) throws -> [String: Any] {
        let url = TestSupport.projectDir().appendingPathComponent(relativePath)
        let data = try Data(contentsOf: url)
        let parsed = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        )
        return parsed as? [String: Any] ?? [:]
    }

    private static func appDocumentTypes() throws -> [[String: Any]] {
        let plist = try plist(at: "NewTheUnarchiver/Info.plist")
        return plist["CFBundleDocumentTypes"] as? [[String: Any]] ?? []
    }

    @Test("Every registry format has exactly one CFBundleDocumentTypes entry")
    func documentTypesMatchRegistry() throws {
        let declared = try Self.appDocumentTypes()
        let declaredUTIs = declared.compactMap {
            ($0["LSItemContentTypes"] as? [String])?.first
        }
        let registryUTIs = SupportedFormats.formats.map(\.utiIdentifier)

        #expect(Set(declaredUTIs) == Set(registryUTIs),
                "drift: \(Set(declaredUTIs).symmetricDifference(Set(registryUTIs)))")
        #expect(declaredUTIs.count == registryUTIs.count, "duplicate document type entries")
    }

    @Test("LSHandlerRank in Info.plist equals the rank declared in the registry")
    func handlerRanksMatchRegistry() throws {
        let declared = try Self.appDocumentTypes()
        var rankByUTI: [String: String] = [:]
        for entry in declared {
            guard let uti = (entry["LSItemContentTypes"] as? [String])?.first else { continue }
            rankByUTI[uti] = entry["LSHandlerRank"] as? String
        }
        for format in SupportedFormats.formats {
            let declaredRank = rankByUTI[format.utiIdentifier] ?? "nil"
            #expect(declaredRank == format.rank.rawValue,
                    "\(format.utiIdentifier): plist says \(declaredRank), registry says \(format.rank.rawValue)")
        }
    }

    @Test("Every app-declared UTI is imported with its extensions")
    func importedTypesCoverAppDeclaredUTIs() throws {
        let plist = try Self.plist(at: "NewTheUnarchiver/Info.plist")
        let imported = plist["UTImportedTypeDeclarations"] as? [[String: Any]] ?? []
        var extensionsByUTI: [String: [String]] = [:]
        for entry in imported {
            guard let uti = entry["UTTypeIdentifier"] as? String,
                  let tags = entry["UTTypeTagSpecification"] as? [String: Any],
                  let exts = tags["public.filename-extension"] as? [String] else { continue }
            extensionsByUTI[uti] = exts
        }

        // Anything in our own reverse-DNS namespace must be declared, because
        // macOS has no built-in type for it.
        let ourNamespace = "aleksei.trankov.newtheunarchiver."
        for format in SupportedFormats.formats
        where format.utiIdentifier.hasPrefix(ourNamespace) {
            let declared = extensionsByUTI[format.utiIdentifier]
            #expect(declared != nil, "\(format.utiIdentifier) is missing from UTImportedTypeDeclarations")
            #expect(declared == format.extensions,
                    "\(format.utiIdentifier): plist lists \(declared ?? []), registry lists \(format.extensions)")
        }
    }

    @Test("Quick Look advertises exactly the registry's types")
    func quickLookTypesMatchRegistry() throws {
        let plist = try Self.plist(at: "NewTheUnarchiverQuickLook/Info.plist")
        let attributes = (plist["NSExtension"] as? [String: Any])?["NSExtensionAttributes"]
            as? [String: Any] ?? [:]
        let supported = attributes["QLSupportedContentTypes"] as? [String] ?? []

        #expect(Set(supported) == Set(SupportedFormats.formats.map(\.utiIdentifier)),
                "Quick Look drift: \(Set(supported).symmetricDifference(Set(SupportedFormats.formats.map(\.utiIdentifier))))")
    }

    @Test("Every format has a localized name in both English and Russian")
    func everyFormatHasLocalizedName() throws {
        let url = TestSupport.projectDir()
            .appendingPathComponent("NewTheUnarchiver/Localizable.xcstrings")
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
            as? [String: Any] ?? [:]
        let strings = catalog["strings"] as? [String: Any] ?? [:]

        for format in SupportedFormats.formats {
            let entry = strings[format.displayNameKey] as? [String: Any]
            #expect(entry != nil, "missing localization key \(format.displayNameKey)")
            let localizations = entry?["localizations"] as? [String: Any] ?? [:]
            for language in ["en", "ru"] {
                let unit = (localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any]
                let value = unit?["value"] as? String
                #expect(value?.isEmpty == false,
                        "\(format.displayNameKey) has no \(language) translation")
            }
        }
    }
}
