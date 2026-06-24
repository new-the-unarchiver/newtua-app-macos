import Foundation

nonisolated enum WrapperMode: String, Sendable, Equatable, Codable, CaseIterable {
    case never
    case onlyIfMultiple
    case always
}

nonisolated enum DestinationStrategy: Sendable, Equatable, Codable {
    case nextToArchive
    case fixed(URL)
    case askEachTime
}

/// User-facing extraction settings. Persisted to `UserDefaults` by `AppModel`
/// — see `AppModel.extractionOptionsKey`. Defaults intentionally match the
/// original The Unarchiver's out-of-the-box behaviour.
nonisolated struct ExtractionOptions: Sendable, Equatable, Codable {
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

    /// Whether a wrapper folder should be created on the Swift side, given
    /// the runtime entry layout. Implements the original Unarchiver
    /// semantics (`.onlyIfMultiple` = more than one top-level item) rather
    /// than the engine's common-root semantics, which diverge for
    /// single-file archives.
    func shouldWrap(topLevelCount: Int) -> Bool {
        switch wrapperMode {
        case .never: false
        case .always: true
        case .onlyIfMultiple: topLevelCount > 1
        }
    }

    /// The directory the engine should actually extract into. Always
    /// resolves on the Swift side — engine receives `wrapper: false` —
    /// so the wrap decision exactly matches `shouldWrap`.
    func resolvedExtractURL(base: URL, archive: URL, topLevelCount: Int) -> URL {
        shouldWrap(topLevelCount: topLevelCount)
            ? base.appendingPathComponent(archive.deletingPathExtension().lastPathComponent)
            : base
    }
}
