import AppKit
import SwiftUI

/// "Extraction" preferences tab. Stores destination, wrapper-folder, and
/// post-action choices on `AppModel.extractionOptions`, which is persisted
/// to `UserDefaults` (see `AppModel.extractionOptionsKey`).
struct ExtractionTab: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            destinationSection
            wrapperSection
            afterSection
        }
        .formStyle(.grouped)
        .padding(20)
    }

    // MARK: - Destination

    private var destinationSection: some View {
        Section("settings.extraction.destination.section") {
            Picker(selection: destinationKindBinding) {
                Text("settings.extraction.destination.nextToArchive")
                    .tag(DestinationKind.nextToArchive)
                Text("settings.extraction.destination.fixed")
                    .tag(DestinationKind.fixed)
                Text("settings.extraction.destination.askEachTime")
                    .tag(DestinationKind.askEachTime)
            } label: {
                EmptyView()
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            if case .fixed(let url) = model.extractionOptions.destinationStrategy {
                HStack {
                    Text(url.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("settings.extraction.destination.browse") {
                        chooseFolder()
                    }
                }
            }
        }
    }

    private enum DestinationKind: Hashable { case nextToArchive, fixed, askEachTime }

    private var destinationKindBinding: Binding<DestinationKind> {
        Binding(
            get: {
                switch model.extractionOptions.destinationStrategy {
                case .nextToArchive: .nextToArchive
                case .fixed: .fixed
                case .askEachTime: .askEachTime
                }
            },
            set: { kind in
                switch kind {
                case .nextToArchive:
                    model.extractionOptions.destinationStrategy = .nextToArchive
                case .fixed:
                    let url: URL
                    if case .fixed(let existing) = model.extractionOptions.destinationStrategy {
                        url = existing
                    } else {
                        url = defaultFolder()
                    }
                    model.extractionOptions.destinationStrategy = .fixed(url)
                case .askEachTime:
                    model.extractionOptions.destinationStrategy = .askEachTime
                }
            }
        )
    }

    private func defaultFolder() -> URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if case .fixed(let current) = model.extractionOptions.destinationStrategy {
            panel.directoryURL = current
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.extractionOptions.destinationStrategy = .fixed(url)
    }

    // MARK: - Wrapper folder

    private var wrapperSection: some View {
        Section("settings.extraction.wrapper.section") {
            Picker(selection: $model.extractionOptions.wrapperMode) {
                Text("settings.extraction.wrapper.never")
                    .tag(WrapperMode.never)
                Text("settings.extraction.wrapper.onlyIfMultiple")
                    .tag(WrapperMode.onlyIfMultiple)
                Text("settings.extraction.wrapper.always")
                    .tag(WrapperMode.always)
            } label: {
                EmptyView()
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
        }
    }

    // MARK: - After extracting

    private var afterSection: some View {
        Section("settings.extraction.after.section") {
            Toggle(
                "settings.extraction.after.openFolder",
                isOn: $model.extractionOptions.openFolderAfter
            )
            Toggle(
                "settings.extraction.after.moveToTrash",
                isOn: $model.extractionOptions.moveToTrashAfter
            )
        }
    }
}
