import Foundation

/// Pure renderer: tree → HTML5 preview document for Quick Look. All
/// user-supplied strings (paths, archive name) are HTML-escaped to keep
/// hostile archive entries from injecting markup into the preview shell.
enum HTMLPreviewRenderer {

    /// Bundle of per-render dependencies — formatters and policy — so
    /// recursive node-render calls take one `ctx` parameter instead of
    /// threading three independent values through every level.
    private struct RenderContext {
        let policy: ExpansionPolicy
        let sizeStyle: ByteCountFormatStyle
        let dateFormatter: DateFormatter
    }

    static func render(
        tree: [TreeNode],
        archiveName: String,
        encrypted: Bool,
        policy: ExpansionPolicy,
        locale: Locale,
        timeZone: TimeZone
    ) -> Data {
        let sizeStyle = ByteCountFormatStyle(
            style: .file, allowedUnits: .all,
            spellsOutZero: false, includesActualByteCount: false,
            locale: locale
        )

        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.timeZone = timeZone
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        let ctx = RenderContext(
            policy: policy, sizeStyle: sizeStyle, dateFormatter: dateFormatter
        )

        // Rough heuristic so the final HTML rarely reallocates: each entry
        // contributes ~250 bytes of markup; plus shell + style.
        var html = ""
        html.reserveCapacity(2_048 + countNodes(tree) * 256)

        html += "<!DOCTYPE html>\n"
        html += "<html><head><meta charset=\"utf-8\">"
        html += "<title>"
        appendEscaped(archiveName, to: &html)
        html += "</title>"
        html += styleBlock()
        html += "</head><body>"
        html += "<header class=\"title\">"
        appendEscaped(archiveName, to: &html)
        html += "</header>"

        if encrypted {
            html += encryptedFallback()
        } else if tree.isEmpty {
            html += emptyState()
        } else {
            html += "<ul class=\"tree\">"
            for node in tree {
                appendNode(node, isRoot: true, ctx: ctx, into: &html)
            }
            html += "</ul>"
        }

        html += "</body></html>"
        return Data(html.utf8)
    }

    // MARK: - Node rendering (append into shared buffer)

    private static func appendNode(
        _ node: TreeNode, isRoot: Bool, ctx: RenderContext, into out: inout String
    ) {
        switch node.kind {
        case .file, .symlink:
            appendLeaf(node, ctx: ctx, into: &out)
        case .directory:
            appendDirectory(node, isRoot: isRoot, ctx: ctx, into: &out)
        }
    }

    private static func appendLeaf(
        _ node: TreeNode, ctx: RenderContext, into out: inout String
    ) {
        let kindClass = node.kind == .symlink ? "leaf symlink" : "leaf file"
        out += "<li class=\"\(kindClass)\">"
        out += "<span class=\"name\">"
        appendEscaped(node.name, to: &out)
        out += "</span>"
        appendMetaSpans(for: node, ctx: ctx, into: &out)
        out += "</li>"
    }

    private static func appendDirectory(
        _ node: TreeNode, isRoot: Bool, ctx: RenderContext, into out: inout String
    ) {
        let open = ctx.policy.shouldExpand(node, isRoot: isRoot) ? " open" : ""
        out += "<li class=\"branch dir\"><details\(open)>"
        out += "<summary><span class=\"name\">"
        appendEscaped(node.name, to: &out)
        out += "</span>"
        appendMetaSpans(for: node, ctx: ctx, into: &out)
        out += "</summary>"
        out += "<ul>"
        for child in node.children {
            appendNode(child, isRoot: false, ctx: ctx, into: &out)
        }
        out += "</ul></details></li>"
    }

    /// Empty `.date`/`.size` spans are required even when there is no
    /// value: the CSS grid uses fixed columns and skips would misalign
    /// the rest of the row.
    private static func appendMetaSpans(
        for node: TreeNode, ctx: RenderContext, into out: inout String
    ) {
        out += "<span class=\"kind\">\(kindLabel(node.kind))</span>"
        appendMetaSpan(class: "date", text: node.mtime.map(ctx.dateFormatter.string(from:)), into: &out)
        appendMetaSpan(class: "size", text: node.size.map { Int64($0).formatted(ctx.sizeStyle) }, into: &out)
    }

    private static func appendMetaSpan(class cls: String, text: String?, into out: inout String) {
        out += "<span class=\"\(cls)\">"
        if let text { appendEscaped(text, to: &out) }
        out += "</span>"
    }

    private static func kindLabel(_ kind: TreeNode.Kind) -> String {
        switch kind {
        case .file: "File"
        case .directory: "Folder"
        case .symlink: "Symlink"
        }
    }

    // MARK: - States

    private static func emptyState() -> String {
        "<div class=\"empty state\"><p>Archive is empty.</p></div>"
    }

    private static func encryptedFallback() -> String {
        "<div class=\"locked state\"><p>This archive is encrypted.</p></div>"
    }

    // MARK: - HTML escaping
    //
    // Fast path: most archive paths contain none of `& < > " '`. Scan the
    // UTF-8 view (cheap) and bail early — that avoids the per-Character
    // loop and the string-concatenation for the common case. The
    // ampersand must be written first in the slow path because we
    // iterate, not chain-replace.

    private static func appendEscaped(_ s: String, to out: inout String) {
        if !needsEscaping(s) {
            out += s
            return
        }
        out.reserveCapacity(out.count + s.count + 8)
        for ch in s.unicodeScalars {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.unicodeScalars.append(ch)
            }
        }
    }

    private static func needsEscaping(_ s: String) -> Bool {
        for b in s.utf8 {
            if b == 0x26 || b == 0x3C || b == 0x3E || b == 0x22 || b == 0x27 {
                return true
            }
        }
        return false
    }

    private static func countNodes(_ nodes: [TreeNode]) -> Int {
        var n = 0
        for node in nodes {
            n += 1 + countNodes(node.children)
        }
        return n
    }

    // MARK: - Style

    private static func styleBlock() -> String {
        """
        <style>
        :root { color-scheme: light dark; font: 13px -apple-system, system-ui, sans-serif; }
        body { margin: 0; padding: 12px 16px; }
        header.title { font-weight: 600; padding-bottom: 8px; border-bottom: 1px solid rgba(128,128,128,0.3); margin-bottom: 8px; }
        ul.tree, ul.tree ul { list-style: none; padding-left: 18px; margin: 0; }
        ul.tree { padding-left: 0; }
        li.branch > details > summary, li.leaf { display: grid; grid-template-columns: 1fr 90px 130px 90px; gap: 8px; align-items: baseline; padding: 2px 0; }
        li.leaf .name { padding-left: 14px; }
        details summary { cursor: pointer; list-style: revert; }
        .name { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
        .kind, .date, .size { color: rgba(128,128,128,0.95); font-variant-numeric: tabular-nums; }
        .size { text-align: right; }
        .state { padding: 24px; text-align: center; opacity: 0.7; }
        </style>
        """
    }
}
