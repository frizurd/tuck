import Foundation

/// Actions that can arrive from outside the menu bar: the `tuck://` URL scheme,
/// Shortcuts, Raycast, Alfred, scripts.
public enum Command: Equatable, Sendable {
    case show
    case showAll
    case hide
    case toggle
    case settings

    /// Accepts `tuck://show`, `tuck:show`, `tuck://show-all`, etc.
    public init?(url: URL) {
        guard url.scheme?.lowercased() == "tuck" else { return nil }
        // Read the text after "tuck:" directly; Foundation parses opaque URLs
        // like "tuck:toggle" differently across macOS versions.
        let text = url.absoluteString
        let afterScheme = text[text.index(after: text.firstIndex(of: ":")!)...]
        let name = afterScheme
            .split(whereSeparator: { "?#".contains($0) }).first.map(String.init)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased() ?? ""
        switch name {
        case "show", "reveal": self = .show
        case "show-all", "showall", "reveal-all": self = .showAll
        case "hide", "tuck": self = .hide
        case "toggle": self = .toggle
        case "settings", "preferences": self = .settings
        default: return nil
        }
    }

    /// The visibility a command leads to, given the current one. `nil` for non-visibility commands.
    public func target(from current: BarState) -> BarState? {
        switch self {
        case .show: return .shown
        case .showAll: return .showingAll
        case .hide: return .hidden
        case .toggle: return current.isRevealed ? .hidden : .shown
        case .settings: return nil
        }
    }
}
