import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class Windows: NSObject, NSWindowDelegate {
    private let preferences: Preferences
    private var settingsWindow: NSWindow?
    private var welcomeWindow: NSWindow?

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    func showSettings() {
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: "Tuck Settings",
                                        content: SettingsView(preferences: preferences, showWelcome: { [weak self] in
                                            self?.showWelcome()
                                        }))
        }
        present(settingsWindow)
    }

    func showWelcome() {
        if welcomeWindow == nil {
            let window = makeWindow(title: "Welcome to Tuck", content: WelcomeView { [weak self] openAtLogin in
                guard let self else { return }
                preferences.hasSeenWelcome = true
                if openAtLogin { try? LoginItem.setEnabled(true) }
                welcomeWindow?.close()
            })
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            welcomeWindow = window
        }
        present(welcomeWindow)
    }

    private func makeWindow(title: String, content: some View) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.title = title
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    private func present(_ window: NSWindow?) {
        guard let window else { return }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window == welcomeWindow {
            preferences.hasSeenWelcome = true
            welcomeWindow = nil
        }
        if window == settingsWindow { settingsWindow = nil }
    }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
