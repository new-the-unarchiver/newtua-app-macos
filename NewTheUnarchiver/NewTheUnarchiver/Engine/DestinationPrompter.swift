import AppKit
import Foundation

/// Asks the user where to extract an archive. The only production caller is
/// `AppCoordinator.openURLs` under `destinationStrategy == .askEachTime`.
/// Returning `nil` means "user cancelled" — the archive is not enqueued.
@MainActor
protocol DestinationPrompter: AnyObject {
    func promptForDestination(archive: URL) -> URL?
}

@MainActor
final class SystemDestinationPrompter: DestinationPrompter {
    func promptForDestination(archive: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = archive.deletingLastPathComponent()
        // %@ is the archive filename — used by the localized panel message.
        panel.message = String(
            format: String(localized: "extract.askEachTime.message",
                           comment: "NSOpenPanel header when asking where to extract a specific archive; %@ is the archive's filename"),
            archive.lastPathComponent
        )
        panel.prompt = String(localized: "extract.askEachTime.prompt",
                              comment: "NSOpenPanel confirm-button label for the askEachTime destination picker")
        return panel.runModal() == .OK ? panel.url : nil
    }
}
