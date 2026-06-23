import AppKit
import SwiftUI

/// "Archive Formats" preferences tab. Shows our supported set of formats,
/// who currently opens each one, and lets the user re-assign us as the
/// default — either per-format or in bulk. Source of truth is Launch
/// Services (via `FileAssociationsService`); no UserDefaults persistence.
struct ArchiveFormatsTab: View {
    let model: ArchiveFormatsModel

    @State private var lsError: LocalizedAlertError?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            bulkAction
            formatList
            footer
        }
        .padding(20)
        .onAppear { model.refresh() }
        .alert(item: $lsError) { err in
            Alert(
                title: Text("settings.formats.error.title"),
                message: Text(err.message),
                dismissButton: .default(Text("settings.formats.error.dismiss"))
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("settings.formats.header.title")
                .font(.headline)
            Text("settings.formats.header.body")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var bulkAction: some View {
        HStack {
            Button {
                runWithErrorAlert { try model.setAsDefaultForAll() }
            } label: {
                Text(model.allAreUs
                     ? "settings.formats.allSet"
                     : "settings.formats.makeAllDefault")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.allAreUs)
            Spacer()
        }
    }

    private var formatList: some View {
        List(model.rows) { row in
            ArchiveFormatRow(row: row) {
                runWithErrorAlert {
                    try model.setAsDefault(forUTI: row.format.utiIdentifier)
                }
            }
        }
        .listStyle(.inset)
        .frame(minHeight: 240)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button {
                model.refresh()
            } label: {
                Label("settings.formats.refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
        }
    }

    private func runWithErrorAlert(_ body: () throws -> Void) {
        do { try body() }
        catch {
            lsError = LocalizedAlertError(error: error)
        }
    }
}

/// Wraps a thrown error in an `Identifiable` payload so `.alert(item:)` can
/// drive itself off it. `id` is the localized message so two distinct
/// errors don't collapse into one alert.
private struct LocalizedAlertError: Identifiable {
    let id: String
    let message: String

    init(error: Error) {
        let text = (error as? LocalizedError)?.errorDescription
            ?? (error as CustomStringConvertible).description
        self.message = text
        self.id = text
    }
}

private struct ArchiveFormatRow: View {
    let row: ArchiveFormatsModel.Row
    let onSetAsDefault: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            FormatIcon.image(forUTI: row.format.utiIdentifier)
                .resizable()
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(row.format.displayNameKey))
                    .font(.body)
                Text(formattedExtensions)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            handlerBadge
            Button(action: onSetAsDefault) {
                Text("settings.formats.setAsDefault")
            }
            .disabled(row.isOurApp)
        }
        .padding(.vertical, 4)
    }

    private var formattedExtensions: String {
        row.format.extensions.map { ".\($0)" }.joined(separator: ", ")
    }

    @ViewBuilder
    private var handlerBadge: some View {
        if row.isOurApp {
            Label("settings.formats.thisApp", systemImage: "checkmark.seal.fill")
                .labelStyle(.titleAndIcon)
                .font(.caption)
                .foregroundStyle(.green)
        } else if let display = row.handlerDisplay {
            HStack(spacing: 6) {
                Image(nsImage: display.icon)
                    .resizable()
                    .frame(width: 16, height: 16)
                Text(display.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } else {
            Text("settings.formats.noHandler")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
