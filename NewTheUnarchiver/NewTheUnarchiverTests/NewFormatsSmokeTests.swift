import Foundation
import Newtua
import Testing
@testable import NewTheUnarchiver

/// The app advertises far more types than it used to, and every one of them is
/// a promise: double-click this and we will open it. `SupportedFormats` only
/// records the promise — these tests check the engine actually keeps it, one
/// archive per newly advertised family.
///
/// The fixtures are copies from `newtua-core`; the engine now ships prebuilt in
/// the `newtua-swift` package, so nothing else here proves it can read a
/// SquashFS image or a 40-year-old ARC file.
@Suite("Newly advertised formats really open")
struct NewFormatsSmokeTests {
    /// Fixture, the extension it is advertised under, and what the registry
    /// must say about it.
    private static let cases: [(fixture: String, ext: String)] = [
        ("clear.arc", "arc"),               // ARC — SEA's PC archiver
        ("hello.pp", "pp"),                 // PowerPacker — Amiga cruncher
        ("tree-gzip.squashfs", "squashfs"), // SquashFS image
        ("wim_none.wim", "wim"),            // Windows imaging format
        ("payload.tar.br", "tar.br"),       // Brotli-compressed tar
        ("pkg.conda", "conda"),             // Conda package
    ]

    @Test("Every smoke fixture opens and lists at least one entry")
    func fixturesOpenAndList() throws {
        for probe in Self.cases {
            let url = TestSupport.fixture(probe.fixture)
            let archive = try Archive(path: url.path)
            #expect(archive.count > 0, "\(probe.fixture): engine reported no entries")
            let entries = archive.entries()
            #expect(entries.count == archive.count, "\(probe.fixture): entry list disagrees with count")
        }
    }

    @Test("Every smoke fixture extracts its contents to disk")
    func fixturesExtract() throws {
        for probe in Self.cases {
            let destination = try TestSupport.makeTempDir(prefix: "smoke-\(probe.ext)")
            defer { try? FileManager.default.removeItem(at: destination) }

            let archive = try Archive(path: TestSupport.fixture(probe.fixture).path)
            let report = try archive.extract(to: destination.path)

            #expect(report.extracted > 0, "\(probe.fixture): nothing was extracted")
            #expect(report.aborted == false, "\(probe.fixture): extraction aborted")
            let written = try FileManager.default.contentsOfDirectory(atPath: destination.path)
            #expect(!written.isEmpty, "\(probe.fixture): destination is empty after extraction")
        }
    }

    @Test("Each smoke format's extension is advertised to the system")
    func smokeFormatsAreAdvertised() {
        let advertised = Set(SupportedFormats.fileExtensions)
        for probe in Self.cases {
            #expect(advertised.contains(probe.ext),
                    "\(probe.ext) extracts but is not advertised in SupportedFormats")
        }
    }
}
