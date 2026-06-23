import SwiftUI

/// Inline password prompt that replaces the per-row subtitle while a job is
/// in `.needsPassword`. Submits via a closure so the row stays decoupled from
/// `Scheduler`.
struct PasswordPromptForm: View {
    let reason: PasswordReason
    let onSubmit: (String, Bool) -> Void

    @State private var password: String = ""
    @State private var applyToAll: Bool = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if reason == .wrongPassword {
                Text("job.password.wrong.hint",
                     comment: "Inline hint shown when the previous password attempt was wrong")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack(spacing: 8) {
                SecureField(
                    String(localized: "job.password.placeholder"),
                    text: $password
                )
                .focused($focused)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
                Toggle(isOn: $applyToAll) {
                    Text("job.password.applyToAll",
                         comment: "Toggle: reuse this password for other encrypted archives in the queue")
                }
                .toggleStyle(.checkbox)
                Button(action: submit) {
                    Text("job.password.continue",
                         comment: "Confirm button for the inline password prompt")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(password.isEmpty)
            }
        }
        .onAppear { focused = true }
    }

    private func submit() {
        guard !password.isEmpty else { return }
        onSubmit(password, applyToAll)
    }
}
