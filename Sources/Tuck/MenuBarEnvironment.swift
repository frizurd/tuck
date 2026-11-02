import AppKit
import TuckCore

/// Reads live state of the menu bar that Tuck doesn't own.
enum MenuBarEnvironment {
    static func blockers() -> HideBlockers {
        HideBlockers(pointerInMenuBar: pointerIsInMenuBar(),
                     menuOpen: menuIsOpen(),
                     mouseButtonDown: NSEvent.pressedMouseButtons != 0)
    }

    static func pointerIsInMenuBar() -> Bool {
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) else {
            return false
        }
        // visibleFrame excludes the menu bar; fall back to the standard thickness when it auto-hides.
        let barHeight = max(screen.frame.maxY - screen.visibleFrame.maxY, NSStatusBar.system.thickness)
        return point.y >= screen.frame.maxY - barHeight
    }

    /// True while any app shows a menu, including menus from revealed status icons.
    /// Window layer and bounds are readable without Screen Recording permission.
    static func menuIsOpen() -> Bool {
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return windows.contains { ($0[kCGWindowLayer as String] as? Int) == menuLevel }
    }
}
