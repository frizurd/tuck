import AppKit
import ApplicationServices

/// Reads where the frontmost app's menus end. Needs Accessibility access; without it
/// Tuck still hides icons, but macOS shows its `«` overflow marker while they're hidden.
enum AppMenus {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt and opens the right Settings pane.
    static func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// The right edge (in screen points) of the frontmost app's last menu title.
    static func maxX() -> CGFloat? {
        guard isTrusted, let app = NSWorkspace.shared.menuBarOwningApplication else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.25)
        var menuBar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXMenuBarAttribute as CFString, &menuBar) == .success,
              let menuBar else { return nil }
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menuBar as! AXUIElement, kAXChildrenAttribute as CFString, &children) == .success,
              let items = children as? [AXUIElement] else { return nil }
        let edges = items.compactMap { item -> CGFloat? in
            guard let position = point(item, kAXPositionAttribute), let size = size(item, kAXSizeAttribute),
                  size.width > 0 else { return nil }
            return position.x + size.width
        }
        return edges.max()
    }

    private static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    private static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }
}
