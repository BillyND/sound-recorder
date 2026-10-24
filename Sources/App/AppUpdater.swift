// Auto-update with Sparkle: new versions come from the GitHub releases feed (SUFeedURL in Info.plist),
// signed with the app's EdDSA key and the same code signature, and never install over a recording.

import Combine
import Sparkle
import SwiftUI

@MainActor
final class AppUpdater: NSObject, ObservableObject {
    static let shared = AppUpdater()

    /// Both settings live in Sparkle's own user defaults (SUEnableAutomaticChecks, SUAutomaticallyUpdate).
    @Published var automaticallyChecks = false {
        didSet { if updater.automaticallyChecksForUpdates != automaticallyChecks { updater.automaticallyChecksForUpdates = automaticallyChecks } }
    }
    @Published var automaticallyDownloads = false {
        didSet { if updater.automaticallyDownloadsUpdates != automaticallyDownloads { updater.automaticallyDownloadsUpdates = automaticallyDownloads } }
    }
    @Published private(set) var canCheckForUpdates = false
    /// A downloaded update waiting for the current recording to stop before it relaunches the app.
    @Published private(set) var postponedVersion: String?

    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"

    private var controller: SPUStandardUpdaterController!
    private var updater: SPUUpdater { controller.updater }
    private var pendingInstall: (() -> Void)?
    private var subscriptions: Set<AnyCancellable> = []

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        automaticallyChecks = updater.automaticallyChecksForUpdates
        automaticallyDownloads = updater.automaticallyDownloadsUpdates

        // Sparkle's own update window can change these too; keep the toggles in step.
        updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] value in self?.canCheckForUpdates = value }
            .store(in: &subscriptions)
        updater.publisher(for: \.automaticallyChecksForUpdates)
            .sink { [weak self] value in if self?.automaticallyChecks != value { self?.automaticallyChecks = value } }
            .store(in: &subscriptions)
        updater.publisher(for: \.automaticallyDownloadsUpdates)
            .sink { [weak self] value in if self?.automaticallyDownloads != value { self?.automaticallyDownloads = value } }
            .store(in: &subscriptions)

        // $state fires before the new value is stored; look again once the recording has fully ended.
        RecorderModel.shared.$state
            .filter { $0 == .idle }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.installPostponedUpdate() }
            .store(in: &subscriptions)
    }

    func checkForUpdates() { updater.checkForUpdates() }

    private func installPostponedUpdate() {
        guard let install = pendingInstall, !RecorderModel.shared.isBusy else { return }
        pendingInstall = nil
        postponedVersion = nil
        install()
    }
}

extension AppUpdater: SPUUpdaterDelegate {
    /// An update that is ready to relaunch the app waits while a recording is starting, running or saving.
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard RecorderModel.shared.isBusy else { return false }
        pendingInstall = installHandler
        postponedVersion = item.displayVersionString
        return true
    }
}

/// "Check for Updates…" in the app menu, in the in-app language.
struct CheckForUpdatesCommand: View {
    @ObservedObject var updater: AppUpdater
    @ObservedObject var model: RecorderModel

    var body: some View {
        Button(model.t("update.check")) { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates)
    }
}
