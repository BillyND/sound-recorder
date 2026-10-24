// Recent recordings in the output folder, with play / reveal / delete on hover.

import SwiftUI

struct RecordingsCard: View {
    @EnvironmentObject var model: RecorderModel
    @State private var pendingDelete: Recording?

    var body: some View {
        let t = model.t
        VStack(alignment: .leading, spacing: 8) {
            header(t)
            if model.recordings.isEmpty {
                emptyState(t)
            } else {
                list
            }
        }
        .padding(Theme.Spacing.cardPadding)
        .frame(minHeight: 230, idealHeight: 320, maxHeight: .infinity, alignment: .top)
        .card()
        .confirmationDialog(t("delete.title"), isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            presenting: pendingDelete) { recording in
            Button(t("delete.confirm"), role: .destructive) { model.trash(recording) }
            Button(t("cancel"), role: .cancel) {}
        } message: { recording in
            Text(t("delete.message", recording.name))
        }
    }

    private func header(_ t: Strings) -> some View {
        HStack {
            Text(t("recent.title")).font(.headline)
            Spacer()
            Button { model.revealFolder() } label: {
                Label(t("recent.openFolder"), systemImage: "folder")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Theme.accent)
            .pointerCursor()
            .help(model.outputFolder.path)
        }
        .padding(.horizontal, 6)
    }

    private func emptyState(_ t: Strings) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform").font(.system(size: 26, weight: .light))
            Text(t("recent.empty")).font(.callout)
        }
        .foregroundStyle(Theme.textSecondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The overlay scroller sits in a gutter taken from the card padding, never over the row buttons.
    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(model.recordings) { recording in
                    RecordingRow(recording: recording, onDelete: { pendingDelete = recording })
                }
            }
            .padding(.trailing, Theme.Spacing.scrollerGutter)
            .overlayScrollers()
        }
        .padding(.trailing, -Theme.Spacing.scrollerGutter)
        .frame(maxHeight: .infinity)
    }
}
