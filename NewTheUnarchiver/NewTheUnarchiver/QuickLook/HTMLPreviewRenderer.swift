import Foundation

/// Pure renderer: tree → HTML5 preview document for Quick Look. All
/// user-supplied strings (paths, archive name) are HTML-escaped to keep
/// hostile archive entries from injecting markup into the preview shell.
enum HTMLPreviewRenderer {

    /// Bundle of per-render dependencies — formatters, policy, and a
    /// pre-resolved plural format string for the per-folder item count
    /// (hoisted out of the recursive walk).
    private struct RenderContext {
        let policy: ExpansionPolicy
        let sizeStyle: ByteCountFormatStyle
        let dateFormatter: DateFormatter
        let bundle: Bundle
        let itemCountFormat: String
    }

    static func render(
        tree: [TreeNode],
        archiveName: String,
        encrypted: Bool,
        policy: ExpansionPolicy,
        locale: Locale,
        timeZone: TimeZone,
        bundle: Bundle = .main
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

        let itemCountFormat = NSLocalizedString(
            "preview.folder.itemCount", bundle: bundle, value: "%d items", comment: ""
        )

        let ctx = RenderContext(
            policy: policy, sizeStyle: sizeStyle, dateFormatter: dateFormatter,
            bundle: bundle, itemCountFormat: itemCountFormat
        )

        var nodeCount = 0
        tree.walk { _ in nodeCount += 1 }
        var html = ""
        html.reserveCapacity(2_048 + nodeCount * 256)

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
            appendEncryptedFallback(ctx: ctx, into: &html)
        } else if tree.isEmpty {
            appendEmptyState(ctx: ctx, into: &html)
        } else {
            appendSummary(for: tree, ctx: ctx, into: &html)
            html += "<ul class=\"tree\">"
            for node in tree {
                appendNode(node, isRoot: true, ctx: ctx, into: &html)
            }
            html += "</ul>"
        }

        html += "</body></html>"
        return Data(html.utf8)
    }

    // MARK: - Header summary

    private static func appendSummary(
        for tree: [TreeNode], ctx: RenderContext, into out: inout String
    ) {
        let s = ArchiveSummary.summarize(tree)
        let filesText = localizedPlural(
            key: "preview.summary.files",
            defaultFormat: "%d files",
            count: s.files, ctx: ctx
        )
        let foldersText = localizedPlural(
            key: "preview.summary.folders",
            defaultFormat: "%d folders",
            count: s.folders, ctx: ctx
        )
        let size = Int64(s.totalBytes).formatted(ctx.sizeStyle)
        out += "<div class=\"summary\">"
        appendEscaped(filesText, to: &out)
        out += " · "
        appendEscaped(foldersText, to: &out)
        out += " · "
        appendEscaped(size, to: &out)
        out += "</div>"
    }

    // MARK: - Node rendering

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
        out += "<span class=\"chevron-spacer\"></span>"
        appendIcon(for: node, into: &out)
        out += "<span class=\"name\">"
        appendEscaped(node.name, to: &out)
        out += "</span>"
        out += "<span class=\"count\"></span>"
        appendDateAndSize(for: node, ctx: ctx, into: &out)
        out += "</li>"
    }

    private static func appendDirectory(
        _ node: TreeNode, isRoot: Bool, ctx: RenderContext, into out: inout String
    ) {
        let isOpen = ctx.policy.shouldExpand(node, isRoot: isRoot)
        let openAttr = isOpen ? " open" : ""
        out += "<li class=\"branch dir\"><details\(openAttr)>"
        out += "<summary>"
        out += "<span class=\"chevron\"></span>"
        appendIcon(for: node, into: &out)
        out += "<span class=\"name\">"
        appendEscaped(node.name, to: &out)
        out += "</span>"
        // Counts shown only when collapsed — otherwise the visible children
        // are themselves the answer, the inline number is noise.
        if !isOpen {
            let text = String.localizedStringWithFormat(ctx.itemCountFormat, node.children.count)
            out += "<span class=\"count\">"
            appendEscaped(text, to: &out)
            out += "</span>"
        } else {
            out += "<span class=\"count\"></span>"
        }
        appendDateAndSize(for: node, ctx: ctx, into: &out)
        out += "</summary>"
        out += "<ul>"
        for child in node.children {
            appendNode(child, isRoot: false, ctx: ctx, into: &out)
        }
        out += "</ul></details></li>"
    }

    private static func appendIcon(for node: TreeNode, into out: inout String) {
        let id = IconCatalog.cid(for: node)
        out += "<img class=\"icon\" src=\"cid:\(id)\" alt=\"\">"
    }

    /// Empty `.date`/`.size` spans are required even when there is no
    /// value: the CSS grid uses fixed columns and skipping them would
    /// misalign the rest of the row.
    private static func appendDateAndSize(
        for node: TreeNode, ctx: RenderContext, into out: inout String
    ) {
        appendMetaSpan(class: "date", text: node.mtime.map(ctx.dateFormatter.string(from:)), into: &out)
        appendMetaSpan(class: "size", text: node.size.map { Int64($0).formatted(ctx.sizeStyle) }, into: &out)
    }

    private static func appendMetaSpan(class cls: String, text: String?, into out: inout String) {
        out += "<span class=\"\(cls)\">"
        if let text { appendEscaped(text, to: &out) }
        out += "</span>"
    }

    // MARK: - States

    private static func appendEmptyState(ctx: RenderContext, into out: inout String) {
        out += "<div class=\"empty state\"><p>"
        appendEscaped(localized(key: "preview.state.empty",
                                defaultValue: "Archive is empty.", ctx: ctx),
                      to: &out)
        out += "</p></div>"
    }

    private static func appendEncryptedFallback(ctx: RenderContext, into out: inout String) {
        out += "<div class=\"locked state\"><p>"
        appendEscaped(localized(key: "preview.state.encrypted",
                                defaultValue: "This archive is encrypted.", ctx: ctx),
                      to: &out)
        out += "</p></div>"
    }

    // MARK: - Localization helpers
    //
    // Bundle defaults to `.main` at render entry — that maps to the main
    // app's bundle in app/test context and to the extension's bundle in
    // the Quick Look extension. Each bundle ships its own
    // `Localizable.xcstrings`. If a translation is missing, the
    // `defaultValue` / `defaultFormat` keeps the English text.

    private static func localized(key: String, defaultValue: String, ctx: RenderContext) -> String {
        NSLocalizedString(key, bundle: ctx.bundle, value: defaultValue, comment: "")
    }

    /// Plural-aware. The format must contain `%d` for the count. xcstrings
    /// stores the plural variations per locale (one/few/many/other) and
    /// `String.localizedStringWithFormat` resolves through them.
    private static func localizedPlural(
        key: String, defaultFormat: String, count: Int, ctx: RenderContext
    ) -> String {
        let format = NSLocalizedString(key, bundle: ctx.bundle, value: defaultFormat, comment: "")
        return String.localizedStringWithFormat(format, count)
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

    // MARK: - Style

    private static func styleBlock() -> String {
        """
        <style>
        :root {
            color-scheme: light dark;
            font: 13px -apple-system, system-ui, sans-serif;
            --row-hover: rgba(127,127,127,0.10);
            --rule: rgba(127,127,127,0.22);
            --dim: rgba(127,127,127,0.95);
            --meta-font-size: 12px;
        }
        body { margin: 0; padding: 12px 16px; }
        header.title {
            font-weight: 600; padding-bottom: 4px;
            border-bottom: 1px solid var(--rule); margin-bottom: 4px;
        }
        .summary {
            color: var(--dim); padding-bottom: 8px;
            border-bottom: 1px solid var(--rule); margin-bottom: 6px;
            font-size: var(--meta-font-size);
        }
        ul.tree, ul.tree ul { list-style: none; padding-left: 18px; margin: 0; }
        ul.tree { padding-left: 0; }
        li.branch > details > summary, li.leaf {
            display: grid;
            grid-template-columns: 12px 18px 1fr auto 140px 90px;
            gap: 6px;
            align-items: center;
            padding: 3px 6px;
            border-radius: 4px;
        }
        li.branch > details > summary:hover, li.leaf:hover { background: var(--row-hover); }
        details summary { cursor: pointer; }
        details summary::-webkit-details-marker { display: none; }
        details summary::marker { content: ""; }
        .chevron, .chevron-spacer { width: 12px; text-align: center; color: var(--dim); }
        .chevron::before { content: "▸"; }
        details[open] > summary .chevron::before { content: "▾"; }
        .icon {
            width: 18px; height: 18px;
            object-fit: contain;
            vertical-align: middle;
        }
        .name { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
        .count, .date, .size {
            color: var(--dim);
            font-variant-numeric: tabular-nums;
            font-size: var(--meta-font-size);
        }
        .count { text-align: right; padding: 0 8px; }
        .size { text-align: right; }
        .state { padding: 32px; text-align: center; opacity: 0.7; }
        </style>
        """
    }
}
