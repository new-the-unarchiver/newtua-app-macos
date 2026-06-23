import XCTest

/// UI-test bundle placeholder. The queue window is currently covered by unit
/// tests on `QueueWindowVisibility`, `JobRowDisplay`, and `ArchiveJob`. A real
/// XCUI smoke is held back pending an environment that can attach to the
/// SwiftUI window from a test runner — see decisions.md.
final class NewTheUnarchiverUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }
}
