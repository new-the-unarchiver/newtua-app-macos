import SwiftUI

@main
struct NewTheUnarchiverApp: App {
    @State private var coordinator = AppCoordinator()
    @State private var openPanelPresented = false

    var body: some Scene {
        Window("queue.window.title", id: QueueWindowAccessibility.windowID) {
            QueueWindow(model: coordinator.model, onOpen: coordinator.openURLs)
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
    }
}

/// Owns the long-lived domain + engine state. Held by `@State` on the App so
/// it survives scene re-evaluation. Also the single entry point for "user
/// asked us to open these URLs" — drop, double-click, File ▸ Open… all land
/// here so the scheduler-kick logic lives in one place.
@MainActor
final class AppCoordinator {
    let model: AppModel
    private let scheduler: Scheduler

    init() {
        let model = AppModel(terminalDisplayDelay: 1.2)
        self.model = model
        self.scheduler = Scheduler(model: model)
    }

    /// Add URLs to the queue and kick the scheduler. Returns whether
    /// anything new actually landed — drop destinations use the boolean
    /// to refuse drags whose payload was already in the queue or filtered
    /// out by `AppModel.enqueue` (directories, duplicates).
    @discardableResult
    func openURLs(_ urls: [URL]) -> Bool {
        let before = model.queue.count
        model.enqueue(urls: urls)
        let accepted = model.queue.count > before
        if accepted { scheduler.dispatch() }
        return accepted
    }
}
