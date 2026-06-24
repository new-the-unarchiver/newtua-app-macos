import Foundation
import Testing
@testable import NewTheUnarchiver

// MARK: - TreeBuilder extended

@Suite("Stage 9 extended — TreeBuilder edge cases")
struct Stage9TreeBuilderExtendedTests {

    @Test("symlink stays a leaf, sorted with files (after dirs)")
    func symlinkSortsWithFiles() {
        let input = [
            PreviewInputEntry(path: "dir/x", kind: .file, size: 1, mtime: nil),
            PreviewInputEntry(path: "link", kind: .symlink, size: 0, mtime: nil),
            PreviewInputEntry(path: "z.txt", kind: .file, size: 1, mtime: nil),
        ]
        let nodes = ArchiveTreeBuilder.buildTree(from: input)
        #expect(nodes.map(\.name) == ["dir", "link", "z.txt"])
        #expect(nodes[1].kind == .symlink)
    }

    @Test("explicit `foo/` after `foo/a.txt` does not duplicate, kind stays directory")
    func explicitDirAfterContent() {
        let input = [
            PreviewInputEntry(path: "foo/a.txt", kind: .file, size: 1, mtime: nil),
            PreviewInputEntry(path: "foo/", kind: .dir, size: 0, mtime: nil),
        ]
        let nodes = ArchiveTreeBuilder.buildTree(from: input)
        #expect(nodes.count == 1)
        #expect(nodes[0].kind == .directory)
        #expect(nodes[0].children.count == 1)
    }

    @Test("synthesized directory has nil size and nil mtime")
    func synthesizedDirHasNoMetadata() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let input = [
            PreviewInputEntry(path: "outer/inner/x", kind: .file, size: 7, mtime: now)
        ]
        let nodes = ArchiveTreeBuilder.buildTree(from: input)
        let outer = nodes[0]
        #expect(outer.size == nil && outer.mtime == nil)
        let inner = outer.children[0]
        #expect(inner.size == nil && inner.mtime == nil)
        let leaf = inner.children[0]
        #expect(leaf.size == 7 && leaf.mtime == now)
    }

    @Test("sidecar deeper in path (`a/b/__MACOSX/x`) drops the whole entry")
    func sidecarMidPathDrops() {
        let input = [
            PreviewInputEntry(path: "a/b/__MACOSX/x", kind: .file, size: 1, mtime: nil),
            PreviewInputEntry(path: "a/b/y", kind: .file, size: 1, mtime: nil),
        ]
        let nodes = ArchiveTreeBuilder.buildTree(from: input)
        let a = nodes[0]
        let b = a.children[0]
        #expect(b.children.map(\.name) == ["y"])
    }

    @Test("only-sidecars archive → empty forest (not a stray empty root)")
    func onlySidecars() {
        let input = [
            PreviewInputEntry(path: "__MACOSX/._x", kind: .file, size: 1, mtime: nil),
            PreviewInputEntry(path: ".DS_Store", kind: .file, size: 1, mtime: nil),
        ]
        #expect(ArchiveTreeBuilder.buildTree(from: input).isEmpty)
    }

    @Test("identical paths in input collapse — no duplicate siblings")
    func duplicatePathsCollapse() {
        let input = [
            PreviewInputEntry(path: "x", kind: .file, size: 1, mtime: nil),
            PreviewInputEntry(path: "x", kind: .file, size: 2, mtime: nil),
        ]
        let nodes = ArchiveTreeBuilder.buildTree(from: input)
        #expect(nodes.count == 1)
    }

    @Test("natural-order sort: file2.txt before file10.txt")
    func naturalOrderSort() {
        let input = [
            PreviewInputEntry(path: "file10.txt", kind: .file, size: 1, mtime: nil),
            PreviewInputEntry(path: "file2.txt", kind: .file, size: 1, mtime: nil),
        ]
        let nodes = ArchiveTreeBuilder.buildTree(from: input)
        #expect(nodes.map(\.name) == ["file2.txt", "file10.txt"])
    }
}

// MARK: - ExpansionPolicy extended

@Suite("Stage 9 extended — ExpansionPolicy boundary")
struct Stage9ExpansionPolicyExtendedTests {

    @Test("custom threshold honoured")
    func customThreshold() {
        let policy = ExpansionPolicy(rootAlwaysExpanded: true, maxChildrenForAutoExpand: 2)
        let two = (0..<2).map { TreeNode.file(name: "f\($0)", path: "d/f\($0)", size: 1, mtime: nil) }
        let three = (0..<3).map { TreeNode.file(name: "f\($0)", path: "d/f\($0)", size: 1, mtime: nil) }
        let nodeTwo = TreeNode.directory(name: "d", path: "d/", mtime: nil, children: two)
        let nodeThree = TreeNode.directory(name: "d", path: "d/", mtime: nil, children: three)
        #expect(policy.shouldExpand(nodeTwo, isRoot: false) == true)
        #expect(policy.shouldExpand(nodeThree, isRoot: false) == false)
    }

    @Test("root with rootAlwaysExpanded=false respects child threshold too")
    func rootMayCollapse() {
        let policy = ExpansionPolicy(rootAlwaysExpanded: false, maxChildrenForAutoExpand: 5)
        let manyChildren = (0..<10).map {
            TreeNode.file(name: "f\($0)", path: "f\($0)", size: 1, mtime: nil)
        }
        let root = TreeNode.directory(name: "r", path: "r/", mtime: nil, children: manyChildren)
        #expect(policy.shouldExpand(root, isRoot: true) == false)
    }
}

// MARK: - HTMLPreviewRenderer extended

@Suite("Stage 9 extended — HTMLPreviewRenderer edge cases")
struct Stage9HTMLRendererExtendedTests {

    private func render(
        _ nodes: [TreeNode], encrypted: Bool = false, archiveName: String = "fixture.zip",
        locale: Locale = Locale(identifier: "en_US_POSIX")
    ) -> String {
        let data = HTMLPreviewRenderer.render(
            tree: nodes, archiveName: archiveName, encrypted: encrypted,
            policy: .default, locale: locale,
            timeZone: TimeZone(identifier: "UTC")!
        )
        return String(data: data, encoding: .utf8) ?? ""
    }

    @Test("archive name in <title> and header is HTML-escaped")
    func archiveNameEscaped() {
        let html = render([], archiveName: "<evil>&\"ok\".zip")
        #expect(html.contains("&lt;evil&gt;"))
        #expect(html.contains("&amp;"))
        #expect(html.contains("&quot;"))
        #expect(!html.contains("<evil>"))
    }

    @Test("ampersand-only path is escaped")
    func ampersandEscaped() {
        let html = render([
            TreeNode.file(name: "a & b", path: "a & b", size: 1, mtime: nil)
        ])
        #expect(html.contains("a &amp; b"))
        #expect(!html.contains(">a & b<"))
    }

    @Test("large size renders with mega/giga units")
    func largeSizeUnits() {
        let twoGiB: UInt64 = 2 * 1024 * 1024 * 1024
        let html = render([
            TreeNode.file(name: "big.bin", path: "big.bin", size: twoGiB, mtime: nil)
        ])
        // .file style typically renders ≥ 1 GB. en_US should contain "GB".
        #expect(html.contains("GB"))
    }

    @Test("missing mtime leaves date span empty")
    func missingMtime() {
        let html = render([
            TreeNode.file(name: "x", path: "x", size: 1, mtime: nil)
        ])
        #expect(html.contains("class=\"date\"></span>"))
    }

    @Test("directory uses <details> with `open` when at root level")
    func rootDirIsOpenByDefault() {
        let html = render([
            TreeNode.directory(name: "d", path: "d/", mtime: nil, children: [])
        ])
        #expect(html.contains("<details open>"))
    }

    @Test("directory with > 5 children renders <details> without `open` attribute")
    func crowdedDirIsCollapsed() {
        let many = (0..<6).map {
            TreeNode.file(name: "f\($0).txt", path: "outer/f\($0).txt", size: 1, mtime: nil)
        }
        // Wrap in an outer directory so the crowded one is NOT root.
        let html = render([
            TreeNode.directory(name: "outer", path: "outer/", mtime: nil, children: [
                TreeNode.directory(name: "crowded", path: "outer/crowded/", mtime: nil, children: many)
            ])
        ])
        // Outer is root → `<details open>`. Inner is not root + has 6 kids → `<details>`.
        let occurrences = html.components(separatedBy: "<details open>").count - 1
        #expect(occurrences == 1, "only the outer root <details> should be `open`")
        #expect(html.contains("<details>"))
    }

    @Test("symlink leaf carries a `symlink` class")
    func symlinkClass() {
        let html = render([
            TreeNode.symlink(name: "link", path: "link", size: 0, mtime: nil)
        ])
        #expect(html.contains("symlink"))
    }

    @Test("output is valid UTF-8 even with non-ASCII (CJK) path")
    func nonASCIIPath() {
        let html = render([
            TreeNode.file(name: "日本語.txt", path: "日本語.txt", size: 1, mtime: nil)
        ])
        #expect(html.contains("日本語.txt"))
    }

    @Test("non-empty tree → no empty-state marker leaks into output")
    func noEmptyMarkerWhenPopulated() {
        let html = render([
            TreeNode.file(name: "x", path: "x", size: 1, mtime: nil)
        ])
        #expect(!html.contains("class=\"empty state\""))
    }

    @Test("encrypted fallback does NOT render the tree, even if entries are supplied")
    func encryptedSuppressesTree() {
        let html = render([
            TreeNode.file(name: "secret.bin", path: "secret.bin", size: 1, mtime: nil)
        ], encrypted: true)
        // Locale-independent: marker class is stable across translations.
        #expect(html.contains("class=\"locked state\""))
        #expect(!html.contains("secret.bin"))
    }

    @Test("locale changes date format text (en vs fr month abbreviation)")
    func localeChangesDate() {
        let mtime = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 UTC
        let en = render([
            TreeNode.file(name: "x", path: "x", size: 1, mtime: mtime)
        ], locale: Locale(identifier: "en_US_POSIX"))
        let fr = render([
            TreeNode.file(name: "x", path: "x", size: 1, mtime: mtime)
        ], locale: Locale(identifier: "fr_FR"))
        // Different locale text is sufficient signal — exact strings vary by SDK.
        #expect(en != fr)
    }
}
