import Foundation
import Testing
@testable import NewTheUnarchiver

// MARK: - TreeBuilder

@Suite("Stage 9 — TreeBuilder: flat paths → folder tree")
struct Stage9TreeBuilderTests {

    @Test("single file at root → one file node")
    func singleFileAtRoot() {
        let input = [
            PreviewInputEntry(path: "a.txt", kind: .file, size: 10, mtime: nil)
        ]
        let nodes = ArchiveTreeBuilder.buildTree(from: input)
        #expect(nodes.count == 1)
        let n = nodes[0]
        #expect(n.name == "a.txt")
        #expect(n.kind == .file)
        #expect(n.children.isEmpty)
        #expect(n.size == 10)
    }

    @Test("shared root dir → one folder with children")
    func sharedRootDir() {
        let input = [
            PreviewInputEntry(path: "foo/a.txt", kind: .file, size: 10, mtime: nil),
            PreviewInputEntry(path: "foo/b.txt", kind: .file, size: 20, mtime: nil),
        ]
        let nodes = ArchiveTreeBuilder.buildTree(from: input)
        #expect(nodes.count == 1)
        let foo = nodes[0]
        #expect(foo.name == "foo")
        #expect(foo.kind == .directory)
        #expect(foo.children.count == 2)
        #expect(foo.children.map(\.name) == ["a.txt", "b.txt"])
    }

    @Test("implicit intermediate directories are synthesized")
    func implicitIntermediateDir() {
        // Only "foo/sub/x.txt" given — no explicit entry for "foo/" or "foo/sub/".
        let input = [
            PreviewInputEntry(path: "foo/sub/x.txt", kind: .file, size: 5, mtime: nil)
        ]
        let nodes = ArchiveTreeBuilder.buildTree(from: input)
        #expect(nodes.count == 1)
        let foo = nodes[0]
        #expect(foo.name == "foo")
        #expect(foo.kind == .directory)
        #expect(foo.size == nil, "synthesized dirs have no size")
        #expect(foo.children.count == 1)
        let sub = foo.children[0]
        #expect(sub.name == "sub")
        #expect(sub.kind == .directory)
        #expect(sub.children.map(\.name) == ["x.txt"])
    }

    @Test("macOS sidecars (__MACOSX/, .DS_Store, ._foo) are dropped")
    func skipsMacOSSidecars() {
        let input = [
            PreviewInputEntry(path: "__MACOSX/._x", kind: .file, size: 1, mtime: nil),
            PreviewInputEntry(path: ".DS_Store", kind: .file, size: 1, mtime: nil),
            PreviewInputEntry(path: "foo/._bar", kind: .file, size: 1, mtime: nil),
            PreviewInputEntry(path: "foo/bar", kind: .file, size: 5, mtime: nil),
            PreviewInputEntry(path: "a.txt", kind: .file, size: 5, mtime: nil),
        ]
        let nodes = ArchiveTreeBuilder.buildTree(from: input)
        #expect(nodes.map(\.name) == ["foo", "a.txt"])
        let foo = nodes[0]
        #expect(foo.children.map(\.name) == ["bar"])
    }

    @Test("directories sort before files, lexicographically")
    func sortsDirsBeforeFiles() {
        let input = [
            PreviewInputEntry(path: "b.txt", kind: .file, size: 1, mtime: nil),
            PreviewInputEntry(path: "a/x", kind: .file, size: 1, mtime: nil),
            PreviewInputEntry(path: "c.txt", kind: .file, size: 1, mtime: nil),
            PreviewInputEntry(path: "z/y", kind: .file, size: 1, mtime: nil),
        ]
        let nodes = ArchiveTreeBuilder.buildTree(from: input)
        #expect(nodes.map(\.name) == ["a", "z", "b.txt", "c.txt"])
        #expect(nodes[0].kind == .directory)
        #expect(nodes[1].kind == .directory)
    }

    @Test("explicit `foo/` entry merges with its contents (no duplicate node)")
    func explicitDirEntryMerges() {
        let input = [
            PreviewInputEntry(path: "foo/", kind: .dir, size: 0, mtime: nil),
            PreviewInputEntry(path: "foo/a.txt", kind: .file, size: 5, mtime: nil),
        ]
        let nodes = ArchiveTreeBuilder.buildTree(from: input)
        #expect(nodes.count == 1)
        #expect(nodes[0].name == "foo")
        #expect(nodes[0].kind == .directory)
        #expect(nodes[0].children.map(\.name) == ["a.txt"])
    }

    @Test("empty input → empty forest")
    func emptyInput() {
        #expect(ArchiveTreeBuilder.buildTree(from: []).isEmpty)
    }
}

// MARK: - ExpansionPolicy

@Suite("Stage 9 — ExpansionPolicy: ≤5 children open, root always open")
struct Stage9ExpansionPolicyTests {

    @Test("root level always expanded — regardless of count")
    func rootAlwaysExpanded() {
        let policy = ExpansionPolicy.default
        let manyChildren = (0..<100).map { i in
            TreeNode.file(name: "f\(i).txt", path: "f\(i).txt", size: 1, mtime: nil)
        }
        let root = TreeNode.directory(
            name: "huge", path: "huge/", mtime: nil, children: manyChildren
        )
        #expect(policy.shouldExpand(root, isRoot: true) == true)
    }

    @Test("nested node with 5 children is expanded")
    func fiveChildrenExpanded() {
        let policy = ExpansionPolicy.default
        let children = (0..<5).map { i in
            TreeNode.file(name: "f\(i)", path: "d/f\(i)", size: 1, mtime: nil)
        }
        let node = TreeNode.directory(name: "d", path: "d/", mtime: nil, children: children)
        #expect(policy.shouldExpand(node, isRoot: false) == true)
    }

    @Test("nested node with 6 children is collapsed")
    func sixChildrenCollapsed() {
        let policy = ExpansionPolicy.default
        let children = (0..<6).map { i in
            TreeNode.file(name: "f\(i)", path: "d/f\(i)", size: 1, mtime: nil)
        }
        let node = TreeNode.directory(name: "d", path: "d/", mtime: nil, children: children)
        #expect(policy.shouldExpand(node, isRoot: false) == false)
    }
}

// MARK: - HTMLPreviewRenderer

@Suite("Stage 9 — HTMLPreviewRenderer: tree → HTML preview data")
struct Stage9HTMLRendererTests {

    private func render(_ nodes: [TreeNode], encrypted: Bool = false) -> String {
        let data = HTMLPreviewRenderer.render(
            tree: nodes,
            archiveName: "fixture.zip",
            encrypted: encrypted,
            policy: .default,
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(identifier: "UTC")!
        )
        return String(data: data, encoding: .utf8) ?? ""
    }

    @Test("emits a valid HTML5 document")
    func emitsValidHTMLDocument() {
        let html = render([
            TreeNode.file(name: "a.txt", path: "a.txt", size: 10, mtime: nil)
        ])
        #expect(html.hasPrefix("<!DOCTYPE html>"))
        #expect(html.contains("<html"))
        #expect(html.contains("</html>"))
    }

    @Test("escapes HTML special chars in paths to prevent injection")
    func escapesPathSpecialChars() {
        let html = render([
            TreeNode.file(
                name: "<script>alert('xss')</script>",
                path: "<script>alert('xss')</script>",
                size: 1, mtime: nil
            )
        ])
        #expect(html.contains("&lt;script&gt;"))
        #expect(html.contains("&#39;") || html.contains("&apos;"))
        #expect(!html.contains("<script>alert"), "raw script tag must not appear")
    }

    @Test("includes ByteCountFormatter-formatted size")
    func includesFormattedSize() {
        // 1500 bytes → "1 KB" (decimal) or "1,5 KB" (en) — accept either.
        let html = render([
            TreeNode.file(name: "x.bin", path: "x.bin", size: 1500, mtime: nil)
        ])
        #expect(html.contains("KB") || html.contains("kB") || html.contains("bytes"))
    }

    @Test("includes localized modification date when mtime present")
    func includesLocalizedDate() {
        let epochZero = Date(timeIntervalSince1970: 0)
        let html = render([
            TreeNode.file(name: "x", path: "x", size: 1, mtime: epochZero)
        ])
        // en_US_POSIX + UTC: epoch 0 → year 1970 in the rendered string.
        #expect(html.contains("1970"))
    }

    @Test("empty tree → empty-state message in HTML")
    func emptyTreeEmitsEmptyState() {
        let html = render([])
        // Should still be a valid document, no JS errors, with a recognizable
        // empty-state marker class.
        #expect(html.contains("empty"))
    }

    @Test("encrypted archive → locked fallback page (no entries rendered)")
    func encryptedFallbackPage() {
        let html = render([], encrypted: true)
        #expect(html.contains("encrypted") || html.contains("locked"))
        #expect(html.contains("<!DOCTYPE html>"))
    }
}
