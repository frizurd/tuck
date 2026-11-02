import AppKit
import TuckCore

/// Menu bar artwork. Everything is a template image so it follows the menu bar's
/// light/dark tint and the "reduce transparency" setting automatically.
enum Glyphs {
    static func chevron(for visibility: BarState) -> NSImage {
        let name: String
        switch visibility {
        case .hidden: name = "chevron.left"
        case .shown: name = "chevron.right"
        case .showingAll: name = "chevron.right.2"
        }
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) ?? NSImage()
        image.isTemplate = true
        return image
    }

    /// A thin rounded line: the edge of the hidden section.
    static let divider: NSImage = template(width: 4) { _ in
        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: NSRect(x: 1.25, y: 2.5, width: 1.5, height: 13),
                     xRadius: 0.75, yRadius: 0.75).fill()
    }

    /// A dotted line: the edge of the always-hidden section.
    static let alwaysHiddenDivider: NSImage = template(width: 4) { _ in
        NSColor.black.withAlphaComponent(0.55).setFill()
        for y in stride(from: 3.0, through: 13.0, by: 3.3) {
            NSBezierPath(ovalIn: NSRect(x: 1.1, y: y, width: 1.8, height: 1.8)).fill()
        }
    }

    private static func template(width: CGFloat, draw: @escaping (NSRect) -> Void) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: 18), flipped: false) { rect in
            draw(rect)
            return true
        }
        image.isTemplate = true
        return image
    }
}
