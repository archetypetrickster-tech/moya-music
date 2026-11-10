import AppKit
import Sparkle

extension MusicApp {
    func setupUpdates() {
        // Tests never contact the update server or change update preferences.
        guard !selfTest else { return }
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        updateStateObserver = updaterController?.updater.observe(\.canCheckForUpdates, options: [.new]) {
            [weak self] _, _ in
            DispatchQueue.main.async { self?.refreshUpdateSettings() }
        }
        connectionPanel.onCheckForUpdates = { [weak self] in self?.checkForUpdates(nil) }
        connectionPanel.onAutomaticUpdatesChanged = { [weak self] enabled in
            self?.updaterController?.updater.automaticallyChecksForUpdates = enabled
        }
    }

    @objc func checkForUpdates(_ sender: Any?) {
        guard let controller = updaterController, controller.updater.canCheckForUpdates else { return }
        controller.checkForUpdates(sender)
    }

    func refreshUpdateSettings() {
        connectionPanel.setUpdateState(
            automatic: updaterController?.updater.automaticallyChecksForUpdates ?? false,
            available: updaterController?.updater.canCheckForUpdates ?? false)
    }
}
