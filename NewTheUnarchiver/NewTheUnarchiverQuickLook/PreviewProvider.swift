import Foundation
import Newtua
import QuickLook
import QuickLookUI
import UniformTypeIdentifiers

/// Thin extension boundary: open the archive via `Newtua`, convert each
/// `Entry` into a `PreviewInputEntry`, then hand off to the pure-Swift
/// `ArchiveTreeBuilder` + `HTMLPreviewRenderer` pipeline. The renderer
/// itself is fully unit-tested in the main app target — keep this class
/// thin and side-effect-free above the engine call.
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let fileURL = request.fileURL
        let archiveName = fileURL.lastPathComponent

        let result = openAndList(at: fileURL)
        switch result {
        case .listed(let tree):
            return htmlReply(archiveName: archiveName, tree: tree, encrypted: false)
        case .encrypted:
            return htmlReply(archiveName: archiveName, tree: [], encrypted: true)
        case .failure(let error):
            // Anything other than encrypted is a hard failure — let
            // Quick Look fall back to its generic icon/preview.
            throw error
        }
    }

    // MARK: - Engine boundary

    private enum OpenResult {
        case listed([TreeNode])
        case encrypted
        case failure(Error)
    }

    /// Opens the archive on the current task's thread (Quick Look invokes
    /// `providePreview` off the main actor) and converts entries into the
    /// renderer's input shape. Header-encrypted archives surface as
    /// `.encrypted` so the caller can show the locked fallback page.
    private func openAndList(at fileURL: URL) -> OpenResult {
        do {
            let archive = try Archive(path: fileURL.path)
            let inputs = archive.entries().map(Self.makeInput(from:))
            return .listed(ArchiveTreeBuilder.buildTree(from: inputs))
        } catch let err as NewtuaError where err.code == .encrypted {
            return .encrypted
        } catch {
            return .failure(error)
        }
    }

    private static func makeInput(from entry: Entry) -> PreviewInputEntry {
        let kind: PreviewInputEntry.Kind = switch entry.kind {
        case .file: .file
        case .dir: .dir
        case .symlink: .symlink
        }
        let mtime = entry.mtime.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        return PreviewInputEntry(path: entry.path, kind: kind, size: entry.size, mtime: mtime)
    }

    // MARK: - Reply construction

    private func htmlReply(
        archiveName: String, tree: [TreeNode], encrypted: Bool
    ) -> QLPreviewReply {
        // Pre-render icon PNGs for every distinct cid in the tree.
        // Encrypted fallback has no tree, so the loop is a no-op then.
        let cids = IconCatalog.uniqueCIDs(in: tree)
        let icons = IconRenderer.renderPNGs(for: cids)

        let reply = QLPreviewReply(
            dataOfContentType: .html,
            contentSize: CGSize(width: 900, height: 700)
        ) { reply in
            reply.stringEncoding = .utf8
            return HTMLPreviewRenderer.render(
                tree: tree,
                archiveName: archiveName,
                encrypted: encrypted,
                policy: .default,
                locale: Locale.current,
                timeZone: TimeZone.current
            )
        }
        reply.title = archiveName
        for (cid, data) in icons {
            reply.attachments[cid] = QLPreviewReplyAttachment(data: data, contentType: .png)
        }
        return reply
    }
}
