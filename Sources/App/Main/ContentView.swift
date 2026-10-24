// The main window: header, notices, source picker, recorder card and recent recordings.

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: RecorderModel
    @State private var topHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar()
            // Everything below the title bar row scrolls when the window is short;
            // the recordings card takes the remaining height and scrolls on its own.
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: Theme.Spacing.stack) {
                        VStack(spacing: Theme.Spacing.stack) {
                            NoticeList()
                            SourceSection()
                            RecorderCard()
                        }
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topHeight = $0 }
                        RecordingsCard()
                            .frame(height: max(220, geo.size.height - topHeight - Theme.Spacing.stack - 26))
                    }
                    .padding(.horizontal, Theme.Spacing.windowInset)
                    .padding(.top, 6)
                    .padding(.bottom, Theme.Spacing.windowInset)
                    .overlayScrollers()
                }
                .scrollBounceBehavior(.basedOnSize)
                .defaultScrollAnchor(.top)
            }
        }
        .ignoresSafeArea(edges: .top)  // the header row shares the title bar, clear of the window buttons
        .frame(minWidth: 420, idealWidth: 440, maxWidth: 560, minHeight: 520, idealHeight: 780, maxHeight: .infinity)
        .foregroundStyle(Theme.textPrimary)
        .background(Backdrop())
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshPermissions()
            model.reloadRecordings()
        }
        .onDisappear { Task { await model.stopForQuit() } }  // closing the window finalizes the file
    }
}
