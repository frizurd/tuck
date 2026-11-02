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
/// macOS 26 and later lay status items out right to left. An item that can't be placed
/// moves into the system overflow (the `«` in the menu bar) together with every item on
/// its left. An item that would run into the app menus is ignored instead, which is why
/// the classic 10,000 pt divider stopped working.
///
/// An item that runs into the app menus doesn't fit anywhere, so macOS drops it quietly,
/// without the `«`. So when Tuck can read where the app menus end (that needs
/// Accessibility access), it stretches the divider to just short of them: no room is
/// left for any icon, and no `«` appears.
///
/// Without that access, Tuck aims the divider's left edge at the middle of the notch.
/// It can't be placed there, so macOS moves it and every icon on its left into the
/// system overflow. That always hides them, but macOS shows a `«` while they're hidden.
public enum PushLength {
    /// Room left between the app menus and the stretched divider. Less than any status
    /// icon needs, so nothing fits in it, but enough to absorb the item's own padding.
    public static let menuGap: CGFloat = 10

    /// - Parameters:
    ///   - dividerMaxX: the divider's right edge, which stays put while it grows leftwards.
    ///   - targetLeftEdge: where the stretched divider's left edge should land.
    ///   - legacy: true before macOS 26, where an oversized item simply runs off screen.
    public static func compute(dividerMaxX: CGFloat, targetLeftEdge: CGFloat, legacy: Bool) -> CGFloat {
        if legacy { return legacyPushLength }
        return max(dividerMaxX - targetLeftEdge, 1)
    }

    /// Where the stretched divider's left edge should land.
    /// - Parameter appMenusMaxX: the right edge of the frontmost app's menus, when readable.
    public static func targetLeftEdge(screen: CGRect, notchLeftArea: CGRect?, notchRightArea: CGRect?,
                                      appMenusMaxX: CGFloat? = nil) -> CGFloat {
        if let appMenusMaxX, appMenusMaxX > screen.minX, appMenusMaxX < screen.maxX {
            return appMenusMaxX + menuGap
        }
        if let left = notchLeftArea, let right = notchRightArea, right.minX > left.maxX {
            let notchMid = (left.maxX + right.minX) / 2
            // NSScreen reports these areas relative to the screen on some systems, globally on others.
            let isGlobal = right.minX >= screen.minX && right.maxX <= screen.maxX + 1
            return isGlobal ? notchMid : screen.minX + notchMid
        }
        // Without a notch or readable menus, assume the menus take less than half the bar.
        return screen.midX
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
