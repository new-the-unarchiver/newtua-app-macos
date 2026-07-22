import Foundation
import Testing
import UniformTypeIdentifiers
@testable import NewTheUnarchiver

// MARK: - IconCatalog

@Suite("Stage 9 polish — IconCatalog: stable cid per node")
struct Stage9IconCatalogTests {

    @Test("directory and symlink resolve to fixed bucket cids")
    func fixedBuckets() {
        let dir = TreeNode.directory(name: "d", path: "d/", mtime: nil, children: [])
        let link = TreeNode.symlink(name: "l", path: "l", size: 0, mtime: nil)
        #expect(IconCatalog.cid(for: dir) == IconCatalog.folderCID)
        #expect(IconCatalog.cid(for: link) == IconCatalog.symlinkCID)
    }

    @Test("two files with the same extension share one cid")
    func sameExtensionShareCID() {
        let a = TreeNode.file(name: "a.txt", path: "a.txt", size: 1, mtime: nil)
        let b = TreeNode.file(name: "deep/b.txt", path: "deep/b.txt", size: 1, mtime: nil)
        #expect(IconCatalog.cid(for: a) == IconCatalog.cid(for: b))
    }

    @Test("different extensions get different cids")
    func differentExtensionsDifferentCIDs() {
        let txt = TreeNode.file(name: "a.txt", path: "a.txt", size: 1, mtime: nil)
        let png = TreeNode.file(name: "a.png", path: "a.png", size: 1, mtime: nil)
        #expect(IconCatalog.cid(for: txt) != IconCatalog.cid(for: png))
    }

    @Test("file without extension resolves to the generic file cid")
    func extensionlessFile() {
        let no = TreeNode.file(name: "README", path: "README", size: 1, mtime: nil)
        #expect(IconCatalog.cid(for: no) == IconCatalog.genericFileCID)
    }

    @Test("extension is matched case-insensitively (PNG = png)")
    func extensionCaseInsensitive() {
        let lower = TreeNode.file(name: "a.png", path: "a.png", size: 1, mtime: nil)
        let upper = TreeNode.file(name: "a.PNG", path: "a.PNG", size: 1, mtime: nil)
        #expect(IconCatalog.cid(for: lower) == IconCatalog.cid(for: upper))
    }

    // MARK: - utType resolution (drives the NSWorkspace lookup in extension)

    @Test("folderCID resolves to UTType.folder")
    func folderCIDResolvesToFolder() {
        #expect(IconCatalog.utType(forCID: IconCatalog.folderCID) == .folder)
    }

    @Test("symlinkCID resolves to UTType.symbolicLink")
    func symlinkCIDResolvesToSymlink() {
        #expect(IconCatalog.utType(forCID: IconCatalog.symlinkCID) == .symbolicLink)
    }

    @Test("genericFileCID resolves to UTType.data")
    func genericCIDResolvesToData() {
        #expect(IconCatalog.utType(forCID: IconCatalog.genericFileCID) == .data)
    }

    @Test("extension cid resolves through filenameExtension")
    func extensionCIDResolves() {
        let png = IconCatalog.utType(forCID: "icon-ext-png")
        #expect(png == UTType(filenameExtension: "png"))
    }

    @Test("cid without the icon-ext- prefix falls back to UTType.data")
    func unknownCIDFallsBack() {
        // Note: `icon-ext-anything` may resolve to a *dynamic* UTType
        // for unknown extensions (Apple's behaviour, not ours) — that's
        // OK, the fallback to .data only kicks in for unparseable cids.
        #expect(IconCatalog.utType(forCID: "nonsense") == .data)
        #expect(IconCatalog.utType(forCID: "") == .data)
    }

    @Test("uniqueCIDs walks the whole tree, no duplicates")
    func uniqueCIDsAcrossTree() {
        let tree: [TreeNode] = [
            TreeNode.directory(name: "d", path: "d/", mtime: nil, children: [
                TreeNode.file(name: "x.txt", path: "d/x.txt", size: 1, mtime: nil),
                TreeNode.file(name: "y.png", path: "d/y.png", size: 1, mtime: nil),
            ]),
            TreeNode.file(name: "z.txt", path: "z.txt", size: 1, mtime: nil),
            TreeNode.symlink(name: "ln", path: "ln", size: 0, mtime: nil),
        ]
        let cids = IconCatalog.uniqueCIDs(in: tree)
        // folder, txt, png, symlink — exactly 4 distinct cids.
        #expect(cids.count == 4)
    }
}

// MARK: - ArchiveSummary

@Suite("Stage 9 polish — ArchiveSummary: header totals")
struct Stage9ArchiveSummaryTests {

    @Test("empty tree → zeros")
    func emptyTree() {
        let s = ArchiveSummary.summarize([])
        #expect(s.files == 0 && s.folders == 0 && s.totalBytes == 0)
    }

    @Test("single file at root")
    func singleFile() {
        let s = ArchiveSummary.summarize([
            TreeNode.file(name: "a.txt", path: "a.txt", size: 42, mtime: nil)
        ])
        #expect(s.files == 1 && s.folders == 0 && s.totalBytes == 42)
    }

    @Test("nested folders and files counted recursively")
    func nested() {
        let tree: [TreeNode] = [
            TreeNode.directory(name: "d", path: "d/", mtime: nil, children: [
                TreeNode.file(name: "a", path: "d/a", size: 100, mtime: nil),
                TreeNode.directory(name: "sub", path: "d/sub/", mtime: nil, children: [
                    TreeNode.file(name: "b", path: "d/sub/b", size: 200, mtime: nil)
                ]),
            ]),
            TreeNode.file(name: "c", path: "c", size: 50, mtime: nil),
        ]
        let s = ArchiveSummary.summarize(tree)
        #expect(s.files == 3)
        #expect(s.folders == 2)
        #expect(s.totalBytes == 350)
    }

    @Test("symlinks counted as files (Quick Look has no separate row)")
    func symlinksAsFiles() {
        let s = ArchiveSummary.summarize([
            TreeNode.symlink(name: "l", path: "l", size: 0, mtime: nil),
            TreeNode.file(name: "f", path: "f", size: 10, mtime: nil),
        ])
        #expect(s.files == 2 && s.folders == 0)
    }
}

// MARK: - HTMLPreviewRenderer polish

@Suite("Stage 9 polish — HTMLPreviewRenderer with icons + summary + chevron")
struct Stage9HTMLRendererPolishTests {

    private func render(
        _ nodes: [TreeNode], encrypted: Bool = false,
        archiveName: String = "fixture.zip"
    ) -> String {
        let data = HTMLPreviewRenderer.render(
            tree: nodes, archiveName: archiveName, encrypted: encrypted,
            policy: .default,
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(identifier: "UTC")!
        )
        return String(data: data, encoding: .utf8) ?? ""
    }

    @Test("each leaf gets an <img src='cid:...'> icon")
    func leafHasIconImg() {
        let html = render([
            TreeNode.file(name: "a.txt", path: "a.txt", size: 1, mtime: nil)
        ])
        let txtCID = IconCatalog.cid(for: TreeNode.file(name: "a.txt", path: "a.txt", size: 1, mtime: nil))
        #expect(html.contains("src=\"cid:\(txtCID)\""))
    }

    @Test("each directory gets the folder icon")
    func directoryHasFolderIcon() {
        let html = render([
            TreeNode.directory(name: "d", path: "d/", mtime: nil, children: [])
        ])
        #expect(html.contains("src=\"cid:\(IconCatalog.folderCID)\""))
    }

    @Test("rendered HTML drops the 'kind' text column entirely")
    func noKindColumn() {
        let html = render([
            TreeNode.file(name: "a", path: "a", size: 1, mtime: nil),
            TreeNode.directory(name: "d", path: "d/", mtime: nil, children: []),
        ])
        // We replaced text labels with icons — no "Folder" / "File" / "Symlink" strings.
        #expect(!html.contains(">Folder<"))
        #expect(!html.contains(">File<"))
        #expect(!html.contains(">Symlink<"))
    }

    @Test("archive summary appears in the header — three `·`-separated segments")
    func summaryInHeader() {
        let html = render([
            TreeNode.directory(name: "d", path: "d/", mtime: nil, children: [
                TreeNode.file(name: "a", path: "d/a", size: 1024, mtime: nil)
            ])
        ])
        // Locale-independent: the renderer always emits exactly three
        // segments inside `<div class="summary">…</div>` separated by `·`
        // (files · folders · total size). Exact phrasing is locale-specific
        // so we count separators, not words.
        let opening = "<div class=\"summary\">"
        let closing = "</div>"
        guard let start = html.range(of: opening),
              let end = html.range(of: closing, range: start.upperBound..<html.endIndex)
        else {
            Issue.record("summary block not found")
            return
        }
        let inner = html[start.upperBound..<end.lowerBound]
        #expect(inner.components(separatedBy: " · ").count == 3)
    }

    @Test("encrypted preview emits no summary block")
    func summaryAbsentWhenEncrypted() {
        let html = render([], encrypted: true)
        #expect(!html.contains("class=\"summary\""))
    }

    @Test("empty preview emits no summary block")
    func summaryAbsentWhenEmpty() {
        let html = render([])
        #expect(!html.contains("class=\"summary\""))
    }

    @Test("collapsed directory shows a child count")
    func collapsedDirShowsCount() {
        // 6 children → collapses per ExpansionPolicy.default (≤5 = expanded).
        let kids = (0..<6).map {
            TreeNode.file(name: "f\($0).txt", path: "outer/crowded/f\($0).txt", size: 1, mtime: nil)
        }
        let html = render([
            TreeNode.directory(name: "outer", path: "outer/", mtime: nil, children: [
                TreeNode.directory(
                    name: "crowded", path: "outer/crowded/", mtime: nil, children: kids
                )
            ])
        ])
        // Locale-independent: the count row is the only place "6" lands inside
        // a `count` span. (Sizes are 1 byte each, not 6.)
        #expect(html.contains("class=\"count\">6"))
    }

    @Test("expanded directory does NOT print a child count")
    func expandedDirNoCount() {
        let html = render([
            TreeNode.directory(name: "d", path: "d/", mtime: nil, children: [
                TreeNode.file(name: "a", path: "d/a", size: 1, mtime: nil)
            ])
        ])
        // Inline "1 item" / "1 items" should not appear for expanded folders —
        // would be redundant noise next to the visible children.
        #expect(!html.contains("1 item"))
        #expect(!html.contains("1 items"))
    }

    @Test("encrypted fallback still works after polish")
    func encryptedStillWorks() {
        let html = render([], encrypted: true)
        // Locale-independent: the locked state has a dedicated CSS class.
        #expect(html.contains("class=\"locked state\""))
    }
}

// MARK: - xcstrings synchronization guard

@Suite("Stage 9 polish — preview keys must stay in lockstep between main and extension catalogs")
struct Stage9XcstringsSyncTests {

    private static func loadCatalog(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    private static func previewStrings(in catalog: [String: Any]) -> [String: Any] {
        let strings = catalog["strings"] as? [String: Any] ?? [:]
        return strings.filter { $0.key.hasPrefix("preview.") }
    }

    @Test("preview.* keys match between main app's and extension's xcstrings")
    func previewKeysMatchBetweenCatalogs() throws {
        let project = TestSupport.projectDir()
        let mainURL = project.appendingPathComponent(
            "NewTheUnarchiver/Localizable.xcstrings"
        )
        let extURL = project.appendingPathComponent(
            "NewTheUnarchiverQuickLook/Localizable.xcstrings"
        )
        let mainCatalog = try Self.loadCatalog(at: mainURL)
        let extCatalog = try Self.loadCatalog(at: extURL)
        let mainPreview = Self.previewStrings(in: mainCatalog)
        let extPreview = Self.previewStrings(in: extCatalog)

        let mainKeys = Set(mainPreview.keys)
        let extKeys = Set(extPreview.keys)
        #expect(mainKeys == extKeys, "preview.* keys differ — main: \(mainKeys.symmetricDifference(extKeys))")

        // Per-key: structure must be byte-identical for en+ru translations.
        for key in mainKeys.sorted() {
            let mainEntry = mainPreview[key] as? [String: Any]
            let extEntry = extPreview[key] as? [String: Any]
            let mainJSON = (try? JSONSerialization.data(
                withJSONObject: mainEntry as Any, options: [.sortedKeys]
            )) ?? Data()
            let extJSON = (try? JSONSerialization.data(
                withJSONObject: extEntry as Any, options: [.sortedKeys]
            )) ?? Data()
            #expect(mainJSON == extJSON, "\(key) differs between main and extension catalogs")
        }
    }
}
