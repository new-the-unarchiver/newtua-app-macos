import SwiftUI

/// Inline encoding prompt: picker + live `Result:` preview of the first
/// non-empty entry path under the chosen encoding. Each pick reopens the
/// archive through `EncodingPreviewer`, debounced via `EncodingPromptDebounce`.
struct EncodingPromptForm: View {
    let job: ArchiveJob
    let onSubmit: (String?) -> Void

    @State private var selected: String?
    @State private var preview: String?
    @State private var debounce = EncodingPromptDebounce(window: 0.2)
    @State private var inFlightTask: Task<Void, Never>?

    init(job: ArchiveJob, onSubmit: @escaping (String?) -> Void) {
        self.job = job
        self.onSubmit = onSubmit
        let current: String?
        if case .needsEncoding(let cur) = job.state { current = cur } else { current = nil }
        self._selected = State(initialValue: current)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Picker(selection: $selected) {
                    ForEach(SupportedEncodings.all, id: \.label) { enc in
                        Text(LocalizedStringKey(enc.nameKey)).tag(enc.label)
                    }
                } label: {
                    Text("job.encoding.label",
                         comment: "Label preceding the encoding picker in the inline prompt")
                }
                .pickerStyle(.menu)
                Spacer(minLength: 4)
                Button(action: submit) {
                    Text("job.encoding.continue",
                         comment: "Confirm button for the inline encoding prompt")
                }
                .keyboardShortcut(.defaultAction)
            }
            if let preview {
                HStack(spacing: 4) {
                    Text("job.encoding.resultLabel",
                         comment: "\"Result:\" prefix preceding the previewed filename")
                        .foregroundStyle(.secondary)
                    Text(preview)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.callout)
            }
        }
        .onAppear { triggerPreview(now: .now) }
        .onChange(of: selected) { _, _ in
            triggerPreview(now: .now)
        }
        .onDisappear { inFlightTask?.cancel() }
    }

    private func submit() {
        onSubmit(selected)
    }

    private func triggerPreview(now: Date) {
        let encoding = selected
        switch debounce.submit(encoding, at: now) {
        case .skipNoChange:
            return
        case .runNow:
            schedulePreview(after: 0, encoding: encoding)
        case .scheduleAfter(let interval):
            schedulePreview(after: interval, encoding: encoding)
        }
    }

    private func schedulePreview(after delay: TimeInterval, encoding: String?) {
        inFlightTask?.cancel()
        let url = job.url
        inFlightTask = Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
                if Task.isCancelled { return }
            }
            let result = await EncodingPreviewer.firstFilename(for: url, encoding: encoding)
            if Task.isCancelled { return }
            preview = result
            debounce.recordResolved(encoding, at: .now)
        }
    }
}
