import SwiftUI
import Newtua

struct JobRowView: View {
    let job: ArchiveJob
    let model: AppModel
    let scheduler: Scheduler

    var body: some View {
        let display = JobRowDisplay(job: job)
        HStack(spacing: 12) {
            FormatIcon.image(for: job.url)
                .resizable()
                .interpolation(.high)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(display.title)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(display.title)
                subtitle(for: display.subtitleKind)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                accessory(for: display)
            }
            Spacer(minLength: 8)
            if display.showsCancelButton {
                Button {
                    model.cancel(job)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
                .help(Text("job.cancel.help", comment: "Tooltip for the per-job cancel button"))
                .accessibilityLabel(Text("job.cancel.accessibility", comment: "VoiceOver label for the cancel button"))
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func accessory(for display: JobRowDisplay) -> some View {
        switch display.subtitleKind {
        case .running:
            if let fraction = display.progressFraction {
                ProgressView(value: fraction).progressViewStyle(.linear)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
        case .needsPassword(let reason):
            PasswordPromptForm(reason: reason) { password, applyToAll in
                scheduler.submitPassword(password, applyToAll: applyToAll, for: job)
            }
        case .needsEncoding:
            EncodingPromptForm(job: job) { encoding in
                scheduler.submitEncoding(encoding, for: job)
            }
        case .queued, .succeeded, .failed, .cancelled:
            EmptyView()
        }
    }

    @ViewBuilder
    private func subtitle(for kind: JobRowDisplay.SubtitleKind) -> some View {
        switch kind {
        case .queued:
            Text("job.subtitle.queued", comment: "Row subtitle while the job waits its turn")
        case .running(let path):
            if let path, !path.isEmpty {
                Text(path)
            } else {
                Text("job.subtitle.running", comment: "Row subtitle while extracting, before the first file path arrives")
            }
        case .needsPassword:
            Text("job.subtitle.needsPassword", comment: "Row subtitle when the archive needs a password")
        case .needsEncoding:
            Text("job.subtitle.needsEncoding", comment: "Row subtitle when filename encoding needs picking")
        case .succeeded:
            Text("job.subtitle.succeeded", comment: "Row subtitle after a successful extraction")
        case .failed:
            Text("job.subtitle.failed", comment: "Row subtitle after a failed extraction")
        case .cancelled:
            Text("job.subtitle.cancelled", comment: "Row subtitle after the user cancelled a job")
        }
    }
}
