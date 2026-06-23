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
}
