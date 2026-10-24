// Sound Recorder: record system audio, a microphone or both to WAV with ScreenCaptureKit.

import SwiftUI

@main
struct SoundRecorderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = RecorderModel.shared

    var body: some Scene {
        Window("Sound Recorder", id: "main") {
            ContentView()
                .environmentObject(model)
                .environment(\.locale, model.language.locale)
                .tint(.brand)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 440, height: 800)
        .windowBackgroundDragBehavior(.enabled)
        .commands { CommandGroup(replacing: .newItem) {} }

        Settings {
            SettingsView()
                .environmentObject(model)
                .environment(\.locale, model.language.locale)
                .tint(.brand)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Holding ⌘R must not start and stop recordings over and over.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let isRecordShortcut = event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "r"
            return event.isARepeat && isRecordShortcut ? nil : event
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Quitting while recording first stops capture and finalizes the WAV header.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            let model = RecorderModel.shared
            guard model.isBusy else { return .terminateNow }
            Task { @MainActor in
                await model.stopForQuit()
                sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
    }
}
