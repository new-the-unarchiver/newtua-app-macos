import Foundation
import Testing
@testable import NewTheUnarchiver

@MainActor
@Suite("Stage 5 — open scenarios (extended)")
struct Stage5ExtendedTests {

    @Test("AppCoordinator.openURLs reports true when at least one URL is new")
    func openURLs_returnsTrue_onNew() {
        let coord = AppCoordinator()
        let u = URL(fileURLWithPath: "/tmp/openURLs-test-\(UUID().uuidString).zip")
        #expect(coord.openURLs([u]) == true)
        #expect(coord.model.queue.contains(where: { $0.url == u.standardizedFileURL }))
    }

    @Test("AppCoordinator.openURLs reports false when every URL is already in the queue")
    func openURLs_allDuplicates_returnsFalse() {
        let coord = AppCoordinator()
        let u = URL(fileURLWithPath: "/tmp/openURLs-dup-\(UUID().uuidString).zip")
        _ = coord.openURLs([u])
        #expect(coord.openURLs([u]) == false)
    }
}
