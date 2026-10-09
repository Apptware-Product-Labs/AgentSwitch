// Renders the app icon as a 1024px PNG. Usage: swift scripts/make_icon.swift <output.png>
//
// The mark: two stacked profile cards, the front one active (solid) with an avatar dot,
// the back one receding. Same glyph as the menu bar icon (see StatusIcon in MenuManager).
import AppKit

let out = CommandLine.arguments[1]
let size: CGFloat = 1024

func card(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, r: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r)
}

let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    // macOS icon grid: the rounded square fills ~82% of the canvas.
    let inset = size * 0.09
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let bg = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGradient(colors: [NSColor(calibratedRed: 0.30, green: 0.27, blue: 0.95, alpha: 1),
                        NSColor(calibratedRed: 0.68, green: 0.30, blue: 0.92, alpha: 1)])!
        .draw(in: bg, angle: -60)
    NSColor.white.withAlphaComponent(0.12).setStroke()
    bg.lineWidth = 6
    bg.stroke()

    // Geometry (centered). Back card up-right, front card down-left.
    let w = size * 0.46, h = size * 0.30, r = size * 0.055
    let off = size * 0.09
    let cx = size / 2, cy = size / 2
    let backRect  = (x: cx - w / 2 + off, y: cy - h / 2 + off)
    let frontRect = (x: cx - w / 2 - off * 0.6, y: cy - h / 2 - off * 0.6)

    // Back card: translucent outline.
    let back = card(x: backRect.x, y: backRect.y, w: w, h: h, r: r)
    NSColor.white.withAlphaComponent(0.28).setFill(); back.fill()
    NSColor.white.withAlphaComponent(0.55).setStroke(); back.lineWidth = size * 0.012; back.stroke()

    // Front card: solid, with a soft shadow.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = size * 0.03
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
    shadow.set()
    let front = card(x: frontRect.x, y: frontRect.y, w: w, h: h, r: r)
    NSColor.white.setFill(); front.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Avatar dot + two "text" bars on the front card, in the gradient's purple.
    let ink = NSColor(calibratedRed: 0.42, green: 0.30, blue: 0.93, alpha: 1)
    let pad = size * 0.045
    let dotD = h * 0.42
    let dot = NSBezierPath(ovalIn: NSRect(x: frontRect.x + pad, y: frontRect.y + (h - dotD) / 2, width: dotD, height: dotD))
    ink.setFill(); dot.fill()
    let barX = frontRect.x + pad + dotD + pad * 0.8
    let barW = w - (barX - frontRect.x) - pad
    let barH = size * 0.03
    for (i, frac) in [CGFloat(1.0), 0.62].enumerated() {
        let y = frontRect.y + h / 2 + (i == 0 ? barH * 0.6 : -barH * 1.6)
        let bar = NSBezierPath(roundedRect: NSRect(x: barX, y: y, width: barW * frac, height: barH), xRadius: barH / 2, yRadius: barH / 2)
        ink.withAlphaComponent(i == 0 ? 1 : 0.55).setFill(); bar.fill()
    }
    return true
}

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("icon render failed\n".data(using: .utf8)!)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: out))
