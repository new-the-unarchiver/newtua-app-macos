import SwiftUI

/// Top-level Preferences view. SwiftUI's `Settings { }` scene hands this
/// view a window that opens on ⌘, and is hidden between sessions.
///
/// Three tabs mirroring the original The Unarchiver: Archive Formats,
/// Extraction, Advanced.
struct SettingsScene: View {
    @Bindable var model: AppModel
    let archiveFormatsModel: ArchiveFormatsModel

    var body: some View {
        TabView {
            ArchiveFormatsTab(model: archiveFormatsModel)
                .tabItem {
                    Label("settings.tab.formats", systemImage: "doc.zipper")
                }
            ExtractionTab(model: model)
                .tabItem {
                    Label("settings.tab.extraction", systemImage: "tray.and.arrow.down")
                }
            AdvancedTab(model: model)
                .tabItem {
                    Label("settings.tab.advanced", systemImage: "gearshape.2")
                }
        }
        .frame(width: 620, height: 520)
    }
}
