import CoreGraphics

/// What the user currently sees in the menu bar.
public enum BarState: Equatable, Sendable {
    /// Everything left of the divider is pushed off screen.
    case hidden
    /// The hidden section is visible; the always-hidden section is not.
    case shown
    /// Both sections are visible.
    case showingAll

    public var isRevealed: Bool { self != .hidden }
}

/// Before macOS 26, a status item could be widened to this length to push everything
/// on its left off screen. macOS 26 and later drop a status item that doesn't fit instead.
public let legacyPushLength: CGFloat = 10_000

/// How wide a divider must be to hide the icons on its left.
///
/// What macOS 26 and later do with a stretched status item, measured on macOS 27:
/// - Longer than about half the screen: the item is ignored, so nothing hides.
///   This is why the classic 10,000 pt divider stopped working.
/// - Shorter, with free menu bar space left of it: icons that no longer fit go into the
///   system overflow, and macOS draws a `«` in that free space.
/// - Reaching the app menus: there's no free space for a `«`, so the icons that don't
///   fit are dropped quietly.
///
/// So when Tuck can read where the app menus end (Accessibility) and reaching them stays
/// within the limit, it does that. Otherwise it aims at the middle of the notch, which
/// always hides but shows the `«`.
public enum PushLength {
    /// Room kept between the app menus and a stretched divider, smaller than a `«`.
    public static let menuGap: CGFloat = 10
    /// Stretched items longer than about half the screen are ignored by macOS.
    public static func maximum(screenWidth: CGFloat) -> CGFloat { screenWidth / 2 - 24 }

    /// The width that hides every icon left of a divider whose right edge is `dividerMaxX`.
    /// - Parameters:
    ///   - notchLeftArea, notchRightArea: `NSScreen.auxiliaryTopLeftArea` / `...RightArea`.
    ///   - appMenusMaxX: right edge of the frontmost app's menus, when readable.
    ///   - legacy: true before macOS 26, where an oversized item simply runs off screen.
    public static func compute(dividerMaxX: CGFloat, screen: CGRect, notchLeftArea: CGRect?,
                               notchRightArea: CGRect?, appMenusMaxX: CGFloat?, legacy: Bool) -> CGFloat {
        if legacy { return legacyPushLength }
        let cap = maximum(screenWidth: screen.width)
        if let menus = appMenusMaxX, menus > screen.minX, menus < dividerMaxX {
            let reachMenus = dividerMaxX - menus - menuGap
            if reachMenus <= cap { return max(reachMenus, 1).rounded(.up) }
        }
        let target: CGFloat
        if let notch = notch(screen: screen, left: notchLeftArea, right: notchRightArea) {
            target = (notch.lowerBound + notch.upperBound) / 2
        } else {
            // No notch and no readable menus: assume the menus use under half the bar.
            target = screen.midX
        }
        return min(max(dividerMaxX - target, 1), cap).rounded(.down)
    }

    /// The notch's horizontal extent in global coordinates.
    static func notch(screen: CGRect, left: CGRect?, right: CGRect?) -> ClosedRange<CGFloat>? {
        guard let left, let right, right.minX > left.maxX else { return nil }
        // NSScreen reports these areas relative to the screen on some systems, globally on others.
        let isGlobal = right.minX >= screen.minX && right.maxX <= screen.maxX + 1
        let offset = isGlobal ? 0 : screen.minX
        return (left.maxX + offset)...(right.minX + offset)
    }
}

/// Horizontal positions (in screen points) of Tuck's own status items.
/// The `x` values are left edges; the `MaxX` values are right edges, which don't move
/// when a divider stretches leftwards.
public struct ItemPositions: Equatable, Sendable {
    public var toggle: CGFloat
    public var divider: CGFloat
    public var dividerMaxX: CGFloat
    public var alwaysHiddenDivider: CGFloat?
    public var alwaysHiddenDividerMaxX: CGFloat?

    public init(toggle: CGFloat, divider: CGFloat, dividerMaxX: CGFloat? = nil,
                alwaysHiddenDivider: CGFloat? = nil, alwaysHiddenDividerMaxX: CGFloat? = nil) {
        self.toggle = toggle
        self.divider = divider
        self.dividerMaxX = dividerMaxX ?? divider + 14
        self.alwaysHiddenDivider = alwaysHiddenDivider
        self.alwaysHiddenDividerMaxX = alwaysHiddenDividerMaxX ?? alwaysHiddenDivider.map { $0 + 14 }
    }

    /// Hiding only works when the divider sits left of the chevron. Otherwise widening
    /// the divider would push the chevron itself off screen and strand the user.
    public var dividerIsUsable: Bool { dividerMaxX <= toggle + 1 }

    /// The always-hidden divider must sit left of the regular divider.
    public var alwaysHiddenIsUsable: Bool {
        guard let alwaysHiddenDivider else { return false }
        guard let alwaysHiddenDividerMaxX else { return false }
        return dividerIsUsable && alwaysHiddenDivider < divider && alwaysHiddenDividerMaxX <= divider + 1
    }
}

/// The length each divider should have. `nil` means "natural width" (just its glyph).
public struct DividerLengths: Equatable, Sendable {
    public var divider: CGFloat?
    public var alwaysHiddenDivider: CGFloat?

    public init(divider: CGFloat?, alwaysHiddenDivider: CGFloat?) {
        self.divider = divider
        self.alwaysHiddenDivider = alwaysHiddenDivider
    }

    public static func resolve(_ state: BarState, positions: ItemPositions,
                               push: (_ dividerMaxX: CGFloat) -> CGFloat) -> DividerLengths {
        guard positions.dividerIsUsable else {
            return DividerLengths(divider: nil, alwaysHiddenDivider: nil)
        }
        let canHideAlways = positions.alwaysHiddenIsUsable
        switch state {
        case .hidden:
            // The divider already pushes the always-hidden section off screen.
            return DividerLengths(divider: push(positions.dividerMaxX), alwaysHiddenDivider: nil)
        case .shown:
            let always = positions.alwaysHiddenDividerMaxX.map(push)
            return DividerLengths(divider: nil, alwaysHiddenDivider: canHideAlways ? always : nil)
        case .showingAll:
            return DividerLengths(divider: nil, alwaysHiddenDivider: nil)
        }
    }
}
