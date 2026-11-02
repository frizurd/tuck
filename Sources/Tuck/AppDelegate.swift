import AppKit
import Combine
import TuckCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences.shared
    private var menuBar: MenuBarController?
    private var windows: Windows?
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if handOffToRunningCopy() { return }

        let windows = Windows(preferences: preferences)
        let menuBar = MenuBarController(preferences: preferences)
        menuBar.openSettings = { windows.showSettings() }
        menuBar.openWelcome = { windows.showWelcome() }
        self.windows = windows
        self.menuBar = menuBar

        HotKeyCenter.shared.action = { [weak menuBar] in menuBar?.perform(.toggle) }
        preferences.$shortcut
            .sink { [weak self] shortcut in self?.register(shortcut) }
            .store(in: &subscriptions)

        if !preferences.hasSeenWelcome {
            windows.showWelcome()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let command = Command(url: url) else { continue }
            if command == .settings {
                windows?.showSettings()
            } else {
                menuBar?.perform(command)
            }
        }
    }

    /// Opening Tuck from Finder or Spotlight while it runs shows Settings instead of nothing.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windows?.showSettings()
        return false
    }

    private func register(_ shortcut: Shortcut?) {
        let registered = HotKeyCenter.shared.register(shortcut)
        preferences.shortcutConflict = !registered
    }

    /// Two copies would fight over the same menu bar. Keep the one that was there first.
    private func handOffToRunningCopy() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0 != NSRunningApplication.current }
        guard let existing = others.first else { return false }
        existing.activate()
        if let url = URL(string: "tuck://settings") {
            NSWorkspace.shared.open(url)
        }
        NSApp.terminate(nil)
        return true
    }
}
