// Renders Assets/AppIcon.png (1024×1024). Run: swift scripts/make-icon.swift
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    // Apple's icon grid: 824 pt body centred in 1024, continuous corners.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor.black.setFill()
    squircle.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    NSGradient(colors: [NSColor(red: 0.42, green: 0.40, blue: 0.98, alpha: 1),
                        NSColor(red: 0.20, green: 0.13, blue: 0.55, alpha: 1)])!
        .draw(in: squircle, angle: -90)

    // Soft top sheen.
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.16), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSBezierPath(roundedRect: body.insetBy(dx: 0, dy: 0), xRadius: 185, yRadius: 185), angle: -90)

    // The menu bar.
    let bar = NSRect(x: 172, y: 437, width: 680, height: 150)
    NSColor.white.setFill()
    NSBezierPath(roundedRect: bar, xRadius: 75, yRadius: 75).fill()

    let ink = NSColor(red: 0.20, green: 0.13, blue: 0.55, alpha: 1)

    // Chevron on the right.
    let chevron = NSBezierPath()
    chevron.move(to: NSPoint(x: 762, y: 548))
    chevron.line(to: NSPoint(x: 722, y: 512))
    chevron.line(to: NSPoint(x: 762, y: 476))
    chevron.lineWidth = 22
    chevron.lineCapStyle = .round
    chevron.lineJoinStyle = .round
    ink.setStroke()
    chevron.stroke()

    // Divider.
    ink.withAlphaComponent(0.45).setFill()
    NSBezierPath(roundedRect: NSRect(x: 650, y: 467, width: 14, height: 90), xRadius: 7, yRadius: 7).fill()

    // Icons sliding away to the left, fading as they go.
    let dots: [(x: CGFloat, r: CGFloat, a: CGFloat)] = [(570, 34, 1.0), (470, 30, 0.55), (382, 26, 0.28), (306, 22, 0.12)]
    for dot in dots {
        ink.withAlphaComponent(dot.a).setFill()
        NSBezierPath(ovalIn: NSRect(x: dot.x - dot.r, y: 512 - dot.r, width: dot.r * 2, height: dot.r * 2)).fill()
    }
    return true
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
NSGraphicsContext.restoreGraphicsState()
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Assets/AppIcon.png")
try rep.representation(using: .png, properties: [:])!.write(to: out)
print("Wrote \(out.path)")
