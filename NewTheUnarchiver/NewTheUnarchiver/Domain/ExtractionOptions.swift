import Foundation

enum WrapperMode: Sendable, Equatable {
    case never
    case onlyIfMultiple
    case always
}

enum DestinationStrategy: Sendable, Equatable {
    case nextToArchive
    case fixed(URL)
    case askEachTime
}

struct ExtractionOptions: Sendable, Equatable {
    var wrapperMode: WrapperMode
    var destinationStrategy: DestinationStrategy
    var openFolderAfter: Bool
    var moveToTrashAfter: Bool

    init(
        wrapperMode: WrapperMode = .onlyIfMultiple,
        destinationStrategy: DestinationStrategy = .nextToArchive,
        openFolderAfter: Bool = false,
        moveToTrashAfter: Bool = false
    ) {
        self.wrapperMode = wrapperMode
        self.destinationStrategy = destinationStrategy
        self.openFolderAfter = openFolderAfter
        self.moveToTrashAfter = moveToTrashAfter
    }
}
