import CoreGraphics

/// Which part of the menu bar an icon belongs to, from where the user ⌘-dragged it:
///
///     [ always hidden ] ┆ [ hidden ] ‹ [ visible ]
public enum Section: Int, Comparable, Sendable {
    case visible, hidden, alwaysHidden

    public static func < (lhs: Section, rhs: Section) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One status item owned by another app, as Accessibility reports it.
public struct StatusIcon: Equatable, Sendable {
    public var bundleIdentifier: String
    public var midX: CGFloat

    public init(bundleIdentifier: String, midX: CGFloat) {
        self.bundleIdentifier = bundleIdentifier
        self.midX = midX
    }
}

public enum Sections {
    /// macOS's own controls (clock, Wi-Fi, Control Center…). They can't be hidden per
    /// app, so they're left out and always stay visible.
    public static let systemOwners: Set<String> = [
        "com.apple.MenuBarAgent", "com.apple.controlcenter", "com.apple.systemuiserver"
    ]

    /// Hiding works per app, so each app gets one section. When an app's icons sit in
    /// different sections, the most visible one wins, so an icon you kept visible never
    /// disappears because a sibling is in the hidden part.
    public static func resolve(_ icons: [StatusIcon], chevronMidX: CGFloat,
                               alwaysHiddenMidX: CGFloat?, ownBundle: String?) -> [String: Section] {
        var sections: [String: Section] = [:]
        for icon in icons where icon.bundleIdentifier != ownBundle && !systemOwners.contains(icon.bundleIdentifier) {
            let section: Section
            if icon.midX > chevronMidX {
                section = .visible
            } else if let alwaysHiddenMidX, alwaysHiddenMidX < chevronMidX, icon.midX < alwaysHiddenMidX {
                section = .alwaysHidden
            } else {
                section = .hidden
            }
            sections[icon.bundleIdentifier] = min(sections[icon.bundleIdentifier] ?? section, section)
        }
        return sections
    }

    /// The apps allowed in the menu bar in a given state, sorted for stable comparison.
    public static func allowed(_ sections: [String: Section], in state: BarState) -> [String] {
        let shown: Set<Section>
        switch state {
        case .hidden: shown = [.visible]
        case .shown: shown = [.visible, .hidden]
        case .showingAll: shown = [.visible, .hidden, .alwaysHidden]
        }
        return sections.filter { shown.contains($0.value) }.map(\.key).sorted()
    }
}
