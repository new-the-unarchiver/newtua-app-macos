import SwiftUI

/// "Advanced" preferences tab. Currently hosts only the global default
/// filename encoding. Reuses `SupportedEncodings.all` from the inline
/// per-job picker so both pickers stay in lockstep.
struct AdvancedTab: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("settings.advanced.encoding.section") {
                Picker(
                    "settings.advanced.encoding.label",
                    selection: $model.extractionOptions.defaultEncoding
                ) {
                    ForEach(SupportedEncodings.all, id: \.label) { enc in
                        Text(LocalizedStringKey(enc.nameKey))
                            .tag(enc.label)
                    }
                }
                Text("settings.advanced.encoding.hint")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}
