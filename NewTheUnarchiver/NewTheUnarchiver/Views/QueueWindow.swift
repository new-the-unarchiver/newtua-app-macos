import SwiftUI

/// Accessibility / window-id constants. One place to rename keys so tests,
/// `openWindow(id:)` callers, and SwiftUI tags can't drift.
enum QueueWindowAccessibility {
    static let windowID = "queue"
    static let emptyTitle = "queue.empty.title"
    static func row(for jobID: UUID) -> String { "queue.row.\(jobID.uuidString)" }
}

struct QueueWindow: View {
    let model: AppModel
    let scheduler: Scheduler

    @State private var isDropTargeted: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if model.queue.isEmpty {
                emptyState
            } else {
                queueList
            }
        }
        .frame(minWidth: 480, minHeight: 240)
        .dropDestination(for: URL.self) { urls, _ in
            handleDrop(urls)
        } isTargeted: { isTargeted in
            isDropTargeted = isTargeted
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text("queue.empty.title", comment: "Headline shown when the queue is empty")
                .font(.title2)
                .accessibilityIdentifier(QueueWindowAccessibility.emptyTitle)
            Text("queue.empty.hint", comment: "Hint shown when the queue is empty — invites the user to drop files")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 32)
    }

    @ViewBuilder
    private var queueList: some View {
        List {
            ForEach(model.queue) { job in
                JobRowView(job: job) { model.cancel(job) }
                    .accessibilityIdentifier(QueueWindowAccessibility.row(for: job.id))
            }
        }
        .listStyle(.inset)
    }

    private func handleDrop(_ urls: [URL]) -> Bool {
        model.enqueue(urls: urls)
        scheduler.dispatch()
        return true
    }
}
