import Foundation

/// The live conditions that should postpone an automatic re-hide.
public struct HideBlockers: Equatable, Sendable {
    public var pointerInMenuBar: Bool
    public var menuOpen: Bool
    public var mouseButtonDown: Bool

    public init(pointerInMenuBar: Bool = false, menuOpen: Bool = false, mouseButtonDown: Bool = false) {
        self.pointerInMenuBar = pointerInMenuBar
        self.menuOpen = menuOpen
        self.mouseButtonDown = mouseButtonDown
    }

    /// Re-hiding while someone is using a revealed icon would yank it out from under them.
    public var shouldPostpone: Bool { pointerInMenuBar || menuOpen || mouseButtonDown }
}

public enum AutoHideDelay {
    public static let range: ClosedRange<Double> = 3...60
    public static let defaultSeconds: Double = 10
    /// How long to wait before checking again after a postponed hide.
    public static let retrySeconds: Double = 1.5

    public static func clamp(_ seconds: Double) -> Double {
        guard seconds.isFinite else { return defaultSeconds }
        return min(max(seconds, range.lowerBound), range.upperBound)
    }
}

/// Turns a stream of scroll deltas into discrete toggle requests.
/// Trackpads emit dozens of small events per swipe; one swipe should toggle once.
public struct ScrollGesture: Sendable {
    public var threshold: Double
    public var cooldown: TimeInterval
    private var accumulated: Double = 0
    private var lastFire: TimeInterval = -.infinity
    private var lastEvent: TimeInterval = -.infinity

    public init(threshold: Double = 12, cooldown: TimeInterval = 0.6) {
        self.threshold = threshold
        self.cooldown = cooldown
    }

    /// Returns true when this event completes a gesture that should toggle visibility.
    public mutating func feed(delta: Double, at time: TimeInterval) -> Bool {
        if time - lastEvent > 0.3 { accumulated = 0 }
        lastEvent = time
        guard time - lastFire >= cooldown else { return false }
        accumulated += abs(delta)
        guard accumulated >= threshold else { return false }
        accumulated = 0
        lastFire = time
        return true
    }
}
