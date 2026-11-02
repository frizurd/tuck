import Foundation
import TuckCore

@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults: UserDefaults

    @Published var autoHide: Bool {
        didSet { defaults.set(autoHide, forKey: Key.autoHide) }
    }
    @Published var autoHideDelay: Double {
        didSet { defaults.set(autoHideDelay, forKey: Key.autoHideDelay) }
    }
    @Published var alwaysHiddenSection: Bool {
        didSet { defaults.set(alwaysHiddenSection, forKey: Key.alwaysHiddenSection) }
    }
    @Published var scrollToToggle: Bool {
        didSet { defaults.set(scrollToToggle, forKey: Key.scrollToToggle) }
    }
    @Published var shortcut: Shortcut? {
        didSet {
            let data = shortcut.flatMap { try? JSONEncoder().encode($0) }
            defaults.set(data, forKey: Key.shortcut)
        }
    }
    @Published var hasSeenWelcome: Bool {
        didSet { defaults.set(hasSeenWelcome, forKey: Key.hasSeenWelcome) }
    }

    /// Set when another app already owns the recorded shortcut. Not persisted.
    @Published var shortcutConflict = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.autoHide: true,
            Key.autoHideDelay: AutoHideDelay.defaultSeconds,
            Key.alwaysHiddenSection: false,
            Key.scrollToToggle: true,
            Key.hasSeenWelcome: false
        ])
        autoHide = defaults.bool(forKey: Key.autoHide)
        autoHideDelay = AutoHideDelay.clamp(defaults.double(forKey: Key.autoHideDelay))
        alwaysHiddenSection = defaults.bool(forKey: Key.alwaysHiddenSection)
        scrollToToggle = defaults.bool(forKey: Key.scrollToToggle)
        hasSeenWelcome = defaults.bool(forKey: Key.hasSeenWelcome)
        shortcut = defaults.data(forKey: Key.shortcut).flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) }
    }

    private enum Key {
        static let autoHide = "autoHide"
        static let autoHideDelay = "autoHideDelay"
        static let alwaysHiddenSection = "alwaysHiddenSection"
        static let scrollToToggle = "scrollToToggle"
        static let shortcut = "shortcut"
        static let hasSeenWelcome = "hasSeenWelcome"
    }
}
