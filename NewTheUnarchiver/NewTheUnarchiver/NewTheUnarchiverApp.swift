import SwiftUI

@main
struct NewTheUnarchiverApp: App {
    @State private var coordinator = AppCoordinator()

    var body: some Scene {
        WindowGroup("queue.window.title", id: QueueWindowAccessibility.windowID) {
            QueueWindow(model: coordinator.model, scheduler: coordinator.scheduler)
        }
        .windowResizability(.contentMinSize)
    }
}

/// Owns the long-lived domain + engine state. Held by `@State` on the App so
/// it survives scene re-evaluation.
@MainActor
final class AppCoordinator {
    let model: AppModel
    let scheduler: Scheduler

    init() {
        let model = AppModel(terminalDisplayDelay: 1.2)
        self.model = model
        self.scheduler = Scheduler(model: model)
    }
}
