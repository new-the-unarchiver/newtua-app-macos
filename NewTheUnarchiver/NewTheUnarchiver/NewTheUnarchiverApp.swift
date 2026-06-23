import SwiftUI

@main
struct NewTheUnarchiverApp: App {
    @State private var coordinator = AppCoordinator()
    @State private var openPanelPresented = false

    var body: some Scene {
        Window("queue.window.title", id: QueueWindowAccessibility.windowID) {
            QueueWindow(
                model: coordinator.model,
                scheduler: coordinator.scheduler,
                onOpen: coordinator.openURLs
            )
                .onOpenURL { url in
                    coordinator.openURLs([url])
                }
                .fileImporter(
                    isPresented: $openPanelPresented,
                    allowedContentTypes: SupportedFormats.utTypes,
                    allowsMultipleSelection: true
                ) { result in
                    if case .success(let urls) = result {
                        coordinator.openURLs(urls)
                    }
                }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button {
                    openPanelPresented = true
                } label: {
                    Text("file.open.menu", comment: "File ▸ Open… menu item")
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }

        Settings {
            SettingsScene(
                model: coordinator.model,
                archiveFormatsModel: coordinator.archiveFormatsModel
            )
        }
    }
}

/// Owns the long-lived domain + engine state. Held by `@State` on the App so
/// it survives scene re-evaluation. Also the single entry point for "user
/// asked us to open these URLs" — drop, double-click, File ▸ Open… all land
/// here so the scheduler-kick logic lives in one place.
@MainActor
final class AppCoordinator {
    let model: AppModel
    let scheduler: Scheduler
    let archiveFormatsModel: ArchiveFormatsModel
    let destinationPrompter: DestinationPrompter

    init(
        defaults: UserDefaults = .standard,
        destinationPrompter: DestinationPrompter? = nil
    ) {
        let model = AppModel(terminalDisplayDelay: 1.2, defaults: defaults)
        self.model = model
        self.scheduler = Scheduler(model: model)
        self.archiveFormatsModel = ArchiveFormatsModel(
            service: LaunchServicesFileAssociations(),
            ourBundleID: Bundle.main.bundleIdentifier ?? ""
        )
        self.destinationPrompter = destinationPrompter ?? SystemDestinationPrompter()
    }

    /// Add URLs to the queue and kick the scheduler. Returns whether
    /// anything new actually landed — drop destinations use the boolean
    /// to refuse drags whose payload was already in the queue or filtered
    /// out (directories, duplicates).
    ///
    /// For `.askEachTime` the destination panel is shown per archive;
    /// archives the user cancels are silently skipped.
    @discardableResult
    func openURLs(_ urls: [URL]) -> Bool {
        // Filter directories before any strategy work — `.askEachTime`
        // would otherwise pop an NSOpenPanel for a folder that `enqueue`
        // is about to discard anyway.
        let files = urls.filter { $0.isFileURL && !$0.hasDirectoryPath }
        let before = model.queue.count

        switch model.extractionOptions.destinationStrategy {
        case .nextToArchive:
            model.enqueue(urls: files)
        case .fixed(let fixed):
            model.enqueue(urls: files, destinationOverride: fixed)
        case .askEachTime:
            for url in files {
                guard let chosen = destinationPrompter.promptForDestination(
                    archive: url.standardizedFileURL
                ) else { continue }
                model.enqueue(urls: [url], destinationOverride: chosen)
            }
        }

        let accepted = model.queue.count > before
        if accepted { scheduler.dispatch() }
        return accepted
    }
}
