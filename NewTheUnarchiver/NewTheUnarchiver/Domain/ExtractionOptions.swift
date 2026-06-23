import Foundation

enum WrapperMode: String, Sendable, Equatable, Codable, CaseIterable {
    case never
    case onlyIfMultiple
    case always
}

enum DestinationStrategy: Sendable, Equatable, Codable {
    case nextToArchive
    case fixed(URL)
    case askEachTime
}

/// User-facing extraction settings. Persisted to `UserDefaults` by `AppModel`
/// — see `AppModel.extractionOptionsKey`. Defaults intentionally match the
/// original The Unarchiver's out-of-the-box behaviour.
struct ExtractionOptions: Sendable, Equatable, Codable {
    var wrapperMode: WrapperMode
    var destinationStrategy: DestinationStrategy
    var openFolderAfter: Bool
    var moveToTrashAfter: Bool
    /// Override the engine's auto-detected filename encoding. `nil` = let
    /// `newtua-core` auto-detect (the original behaviour). Set from the
    /// Advanced Preferences tab; used as a starting point by `JobRunner`
    /// when the job has no per-job `pendingEncoding`.
    var defaultEncoding: String?

    init(
        wrapperMode: WrapperMode = .onlyIfMultiple,
        destinationStrategy: DestinationStrategy = .nextToArchive,
        openFolderAfter: Bool = false,
        moveToTrashAfter: Bool = false,
        defaultEncoding: String? = nil
    ) {
        self.wrapperMode = wrapperMode
        self.destinationStrategy = destinationStrategy
        self.openFolderAfter = openFolderAfter
        self.moveToTrashAfter = moveToTrashAfter
        self.defaultEncoding = defaultEncoding
    }

    /// What to pass as the engine's `wrapper:` flag. Only `.onlyIfMultiple`
    /// asks the engine to wrap — `.always` creates the wrapper on the Swift
    /// side (`resolvedExtractURL`), `.never` extracts flat.
    var wrapperFlag: Bool {
        wrapperMode == .onlyIfMultiple
    }

    /// The directory the engine should actually extract into. For
    /// `.never`/`.onlyIfMultiple` this is the user-chosen base. For
    /// `.always` we append the archive's stem so the engine writes into
    /// `<base>/<stem>/` with `wrapperFlag == false`.
    func resolvedExtractURL(base: URL, archive: URL) -> URL {
        switch wrapperMode {
        case .never, .onlyIfMultiple:
            return base
        case .always:
            return base.appendingPathComponent(archive.deletingPathExtension().lastPathComponent)
        }
    }
}
