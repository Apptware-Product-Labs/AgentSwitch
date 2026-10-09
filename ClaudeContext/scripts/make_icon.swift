// Renders the app icon as a 1024px PNG. Usage: swift scripts/make_icon.swift <output.png>
import AppKit

let out = CommandLine.arguments[1]
let size: CGFloat = 1024

let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    // macOS icon grid: the rounded square fills ~82% of the canvas.
    let inset = size * 0.09
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let bg = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)

    NSGradient(colors: [NSColor(calibratedRed: 0.36, green: 0.33, blue: 0.95, alpha: 1),
                        NSColor(calibratedRed: 0.62, green: 0.30, blue: 0.90, alpha: 1)])!
        .draw(in: bg, angle: -60)

    // Subtle inner highlight.
    NSColor.white.withAlphaComponent(0.12).setStroke()
    bg.lineWidth = 6
    bg.stroke()

    let config = NSImage.SymbolConfiguration(pointSize: size * 0.46, weight: .semibold)
    guard let symbol = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else { return false }

    // Tint white.
    let tinted = NSImage(size: symbol.size, flipped: false) { r in
        symbol.draw(in: r)
        NSColor.white.set()
        r.fill(using: .sourceAtop)
        return true
    }
    let s = tinted.size
    let origin = NSPoint(x: (size - s.width) / 2, y: (size - s.height) / 2 + size * 0.01)
    // Soft shadow for depth.
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    tinted.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
    return true
}

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("icon render failed\n".data(using: .utf8)!)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: out))
