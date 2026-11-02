import XCTest
@testable import TuckCore

final class LayoutTests: XCTestCase {
    let correct = ItemPositions(toggle: 1200, divider: 1170, alwaysHiddenDivider: 1000)
    let pushLength: CGFloat = 777
    func resolve(_ state: BarState, _ positions: ItemPositions) -> DividerLengths {
        DividerLengths.resolve(state, positions: positions) { _ in self.pushLength }
    }

    func testHiddenPushesOnlyTheDivider() {
        XCTAssertEqual(resolve(.hidden, correct),
                       DividerLengths(divider: self.pushLength, alwaysHiddenDivider: nil))
    }

    func testShownKeepsAlwaysHiddenSectionAway() {
        XCTAssertEqual(resolve(.shown, correct),
                       DividerLengths(divider: nil, alwaysHiddenDivider: self.pushLength))
    }

    func testShowingAllCollapsesNothing() {
        XCTAssertEqual(resolve(.showingAll, correct),
                       DividerLengths(divider: nil, alwaysHiddenDivider: nil))
    }

    func testDividerRightOfChevronNeverHides() {
        let wrong = ItemPositions(toggle: 1200, divider: 1230, alwaysHiddenDivider: 1000)
        XCTAssertFalse(wrong.dividerIsUsable)
        for visibility in [BarState.hidden, .shown, .showingAll] {
            XCTAssertEqual(resolve(visibility, wrong),
                           DividerLengths(divider: nil, alwaysHiddenDivider: nil))
        }
    }

    func testAlwaysHiddenDividerRightOfDividerIsIgnored() {
        let wrong = ItemPositions(toggle: 1200, divider: 1170, alwaysHiddenDivider: 1180)
        XCTAssertFalse(wrong.alwaysHiddenIsUsable)
        XCTAssertEqual(resolve(.shown, wrong),
                       DividerLengths(divider: nil, alwaysHiddenDivider: nil))
        XCTAssertEqual(resolve(.hidden, wrong),
                       DividerLengths(divider: self.pushLength, alwaysHiddenDivider: nil))
    }

    func testNoAlwaysHiddenSection() {
        let positions = ItemPositions(toggle: 1200, divider: 1170)
        XCTAssertEqual(resolve(.shown, positions),
                       DividerLengths(divider: nil, alwaysHiddenDivider: nil))
    }

    func testStretchedDividerStaysUsable() {
        // While hidden the divider grows leftwards; its right edge stays put.
        let hidden = ItemPositions(toggle: 1108, divider: 484, dividerMaxX: 1100)
        XCTAssertTrue(hidden.dividerIsUsable)
    }

    func testPushUsesEachDividersRightEdge() {
        let positions = ItemPositions(toggle: 1200, divider: 1170, dividerMaxX: 1184,
                                      alwaysHiddenDivider: 1000, alwaysHiddenDividerMaxX: 1014)
        let lengths = DividerLengths.resolve(.shown, positions: positions) { $0 - 956 }
        XCTAssertEqual(lengths.alwaysHiddenDivider, 58)
        let hidden = DividerLengths.resolve(.hidden, positions: positions) { $0 - 956 }
        XCTAssertEqual(hidden.divider, 228)
    }
}

final class PushLengthTests: XCTestCase {
    // Measured on a 14" MacBook Pro running macOS 27.
    let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    let notchLeft = CGRect(x: 0, y: 1085, width: 771.5, height: 32)
    let notchRight = CGRect(x: 956.5, y: 1085, width: 771.5, height: 32)

    func push(_ maxX: CGFloat, menus: CGFloat?, screen: CGRect? = nil, notch: Bool = true) -> CGFloat {
        PushLength.compute(dividerMaxX: maxX, screen: screen ?? self.screen,
                           notchLeftArea: notch ? notchLeft : nil, notchRightArea: notch ? notchRight : nil,
                           appMenusMaxX: menus, legacy: false)
    }

    func testReachesLongMenus() {
        // Mail's menus end around x=534: reaching them leaves no room for a «.
        XCTAssertEqual(push(1348, menus: 534), 804)
    }

    func testShortMenusOutOfReachFallBackToTheNotch() {
        // Reaching x=370 would take 968 pt, more than macOS accepts.
        XCTAssertEqual(push(1348, menus: 370), 484)
    }

    func testFallsBackWhenMenusAreUnreadable() {
        XCTAssertEqual(push(1348, menus: nil), 484)
    }

    func testNeverLongerThanMacOSAccepts() {
        XCTAssertLessThanOrEqual(push(1720, menus: nil), PushLength.maximum(screenWidth: 1728))
        XCTAssertLessThanOrEqual(push(1720, menus: 300), PushLength.maximum(screenWidth: 1728))
    }

    func testNoNotchReachesTheMenus() {
        let external = CGRect(x: 1728, y: 0, width: 2560, height: 1440)
        XCTAssertEqual(push(3500, menus: 2300, screen: external, notch: false), 1190)
        XCTAssertEqual(push(4000, menus: nil, screen: external, notch: false), 992)
    }

    func testNotchAreasRelativeToAnOffsetScreen() {
        let offset = CGRect(x: -1728, y: 0, width: 1728, height: 1117)
        XCTAssertEqual(PushLength.notch(screen: offset, left: notchLeft, right: notchRight), -956.5 ... -771.5)
    }

    func testLegacySystemsKeepClassicPush() {
        XCTAssertEqual(PushLength.compute(dividerMaxX: 1100, screen: screen, notchLeftArea: nil, notchRightArea: nil,
                                          appMenusMaxX: nil, legacy: true), legacyPushLength)
    }

    func testNeverZeroOrNegative() {
        XCTAssertEqual(push(800, menus: nil), 1)
    }
}

final class AutoHideTests: XCTestCase {
    func testPostponesWhileInUse() {
        XCTAssertFalse(HideBlockers().shouldPostpone)
        XCTAssertTrue(HideBlockers(pointerInMenuBar: true).shouldPostpone)
        XCTAssertTrue(HideBlockers(menuOpen: true).shouldPostpone)
        XCTAssertTrue(HideBlockers(mouseButtonDown: true).shouldPostpone)
    }

    func testDelayClamp() {
        XCTAssertEqual(AutoHideDelay.clamp(0), 3)
        XCTAssertEqual(AutoHideDelay.clamp(500), 60)
        XCTAssertEqual(AutoHideDelay.clamp(.nan), 10)
        XCTAssertEqual(AutoHideDelay.clamp(15), 15)
    }

    func testScrollSwipeTogglesOnce() {
        var gesture = ScrollGesture(threshold: 12, cooldown: 0.6)
        var fired = 0
        for step in 0..<30 {
            if gesture.feed(delta: 3, at: Double(step) * 0.016) { fired += 1 }
        }
        XCTAssertEqual(fired, 1)
    }

    func testScrollSecondSwipeAfterCooldown() {
        var gesture = ScrollGesture(threshold: 12, cooldown: 0.6)
        XCTAssertFalse(gesture.feed(delta: 6, at: 0))
        XCTAssertTrue(gesture.feed(delta: -6, at: 0.01))
        XCTAssertFalse(gesture.feed(delta: 20, at: 0.3))
        XCTAssertTrue(gesture.feed(delta: 20, at: 1.0))
    }

    func testTinyJitterNeverToggles() {
        var gesture = ScrollGesture(threshold: 12, cooldown: 0.6)
        for step in 0..<10 {
            XCTAssertFalse(gesture.feed(delta: 1, at: Double(step) * 0.5))
        }
    }
}

final class ShortcutTests: XCTestCase {
    func testDisplayOrder() {
        let shortcut = Shortcut(keyCode: 4, modifiers: [.command, .control, .option, .shift], keyLabel: "H")
        XCTAssertEqual(shortcut.displayString, "⌃⌥⇧⌘H")
    }

    func testNeedsRealModifierUnlessFunctionKey() {
        XCTAssertFalse(Shortcut(keyCode: 4, modifiers: [], keyLabel: "H").isAcceptable)
        XCTAssertFalse(Shortcut(keyCode: 4, modifiers: [.shift], keyLabel: "H").isAcceptable)
        XCTAssertTrue(Shortcut(keyCode: 4, modifiers: [.option], keyLabel: "H").isAcceptable)
        XCTAssertTrue(Shortcut(keyCode: 105, modifiers: [], keyLabel: "F13").isAcceptable)
    }

    func testRoundTrip() throws {
        let shortcut = Shortcut(keyCode: 49, modifiers: [.command, .option], keyLabel: "Space")
        let decoded = try JSONDecoder().decode(Shortcut.self, from: JSONEncoder().encode(shortcut))
        XCTAssertEqual(decoded, shortcut)
    }
}

final class CommandTests: XCTestCase {
    func testParsesURLs() {
        XCTAssertEqual(Command(url: URL(string: "tuck://show")!), .show)
        XCTAssertEqual(Command(url: URL(string: "tuck://show-all")!), .showAll)
        XCTAssertEqual(Command(url: URL(string: "TUCK://Hide")!), .hide)
        XCTAssertEqual(Command(url: URL(string: "tuck:toggle")!), .toggle)
        XCTAssertEqual(Command(url: URL(string: "tuck://hide?from=raycast")!), .hide)
        XCTAssertEqual(Command(url: URL(string: "tuck://settings")!), .settings)
        XCTAssertNil(Command(url: URL(string: "tuck://explode")!))
        XCTAssertNil(Command(url: URL(string: "https://show")!))
    }

    func testToggleTargets() {
        XCTAssertEqual(Command.toggle.target(from: .hidden), .shown)
        XCTAssertEqual(Command.toggle.target(from: .shown), .hidden)
        XCTAssertEqual(Command.toggle.target(from: .showingAll), .hidden)
        XCTAssertNil(Command.settings.target(from: .hidden))
    }
}

final class SectionsTests: XCTestCase {
    func testSidesOfTheChevron() {
        let icons = [StatusIcon(bundleIdentifier: "left", midX: 900),
                     StatusIcon(bundleIdentifier: "right", midX: 1400),
                     StatusIcon(bundleIdentifier: "com.apple.controlcenter", midX: 800),
                     StatusIcon(bundleIdentifier: "com.frizurd.tuck", midX: 1360)]
        let sections = Sections.resolve(icons, chevronMidX: 1360, alwaysHiddenMidX: nil, ownBundle: "com.frizurd.tuck")
        XCTAssertEqual(sections, ["left": .hidden, "right": .visible])
        XCTAssertEqual(Sections.allowed(sections, in: .hidden), ["right"])
        XCTAssertEqual(Sections.allowed(sections, in: .shown), ["left", "right"])
    }

    func testAlwaysHiddenSection() {
        let icons = [StatusIcon(bundleIdentifier: "far", midX: 700),
                     StatusIcon(bundleIdentifier: "near", midX: 1000)]
        let sections = Sections.resolve(icons, chevronMidX: 1360, alwaysHiddenMidX: 800, ownBundle: nil)
        XCTAssertEqual(sections, ["far": .alwaysHidden, "near": .hidden])
        XCTAssertEqual(Sections.allowed(sections, in: .shown), ["near"])
        XCTAssertEqual(Sections.allowed(sections, in: .showingAll), ["far", "near"])
    }

    func testMisplacedAlwaysHiddenDividerIsIgnored() {
        let icons = [StatusIcon(bundleIdentifier: "a", midX: 700)]
        XCTAssertEqual(Sections.resolve(icons, chevronMidX: 1000, alwaysHiddenMidX: 1200, ownBundle: nil), ["a": .hidden])
    }

    func testMostVisibleIconWinsForAnApp() {
        let icons = [StatusIcon(bundleIdentifier: "multi", midX: 900),
                     StatusIcon(bundleIdentifier: "multi", midX: 1400)]
        XCTAssertEqual(Sections.resolve(icons, chevronMidX: 1360, alwaysHiddenMidX: nil, ownBundle: nil), ["multi": .visible])
    }
}
