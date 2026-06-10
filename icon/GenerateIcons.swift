// Renders three macOS app-icon concepts for UsageMeter at 1024x1024.
// Run: swift icon/GenerateIcons.swift
// Output: icon/icon1-gauge.png, icon/icon2-rings.png, icon/icon3-bars.png
import AppKit

let SIZE: CGFloat = 1024

// MARK: - Helpers

func deg(_ d: CGFloat) -> CGFloat { d }  // AppKit arc APIs take degrees directly

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

/// The macOS "squircle" body: a rounded square inset from the canvas edges.
func bodyPath() -> NSBezierPath {
    let margin: CGFloat = 100
    let rect = NSRect(x: margin, y: margin, width: SIZE - 2 * margin, height: SIZE - 2 * margin)
    return NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
}

func drawBackground(top: UInt32, bottom: UInt32) {
    // Soft drop shadow beneath the body.
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowOffset = NSSize(width: 0, height: -18)
    shadow.shadowBlurRadius = 40
    NSGraphicsContext.current?.saveGraphicsState()
    shadow.set()
    color(top).setFill()
    bodyPath().fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    // Gradient fill clipped to the body.
    NSGraphicsContext.current?.saveGraphicsState()
    bodyPath().addClip()
    let g = NSGradient(starting: color(top), ending: color(bottom))!
    g.draw(in: NSRect(x: 0, y: 0, width: SIZE, height: SIZE), angle: -90)
    // Subtle top sheen.
    let sheen = NSGradient(colors: [NSColor.white.withAlphaComponent(0.22),
                                    NSColor.white.withAlphaComponent(0.0)])!
    sheen.draw(in: NSRect(x: 0, y: SIZE * 0.52, width: SIZE, height: SIZE * 0.48), angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()
}

func render(_ name: String, _ draw: () -> Void) {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(SIZE), pixelsHigh: Int(SIZE),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.current?.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    let url = URL(fileURLWithPath: "icon/\(name)")
    try? rep.representation(using: .png, properties: [:])?.write(to: url)
    print("wrote icon/\(name)")
}

let center = NSPoint(x: SIZE / 2, y: SIZE / 2)

// MARK: - Icon 1: gauge / speedometer

func arc(center c: NSPoint, radius r: CGFloat, from: CGFloat, to: CGFloat,
         width: CGFloat, stroke: NSColor, cap: NSBezierPath.LineCapStyle = .round) {
    let p = NSBezierPath()
    p.appendArc(withCenter: c, radius: r, startAngle: from, endAngle: to, clockwise: true)
    p.lineWidth = width
    p.lineCapStyle = cap
    stroke.setStroke()
    p.stroke()
}

func icon1() {
    drawBackground(top: 0x3A4ED6, bottom: 0x6C2BD9)  // indigo -> violet
    let c = NSPoint(x: SIZE / 2, y: SIZE / 2 - 40)
    let R: CGFloat = 300
    let start: CGFloat = 210, end: CGFloat = 330  // 240° sweep over the top, clockwise
    let value: CGFloat = 0.70

    // Track.
    arc(center: c, radius: R, from: start, to: end, width: 86,
        stroke: NSColor.white.withAlphaComponent(0.22))
    // Filled portion.
    let valAngle = start - value * (start + (360 - end))  // 210 -> ... over top
    arc(center: c, radius: R, from: start, to: valAngle, width: 86,
        stroke: NSColor.white.withAlphaComponent(0.95))

    // Tick marks.
    NSColor.white.withAlphaComponent(0.55).setStroke()
    let ticks = 9
    for i in 0...ticks {
        let t = start - CGFloat(i) / CGFloat(ticks) * 240
        let a = t * .pi / 180
        let inner = R - 58, outer = R - 30
        let p = NSBezierPath()
        p.move(to: NSPoint(x: c.x + cos(a) * inner, y: c.y + sin(a) * inner))
        p.line(to: NSPoint(x: c.x + cos(a) * outer, y: c.y + sin(a) * outer))
        p.lineWidth = 8
        p.lineCapStyle = .round
        p.stroke()
    }

    // Needle.
    let na = valAngle * .pi / 180
    let needle = NSBezierPath()
    let tail: CGFloat = 46
    needle.move(to: NSPoint(x: c.x - cos(na) * tail, y: c.y - sin(na) * tail))
    needle.line(to: NSPoint(x: c.x + cos(na) * (R - 18), y: c.y + sin(na) * (R - 18)))
    needle.lineWidth = 26
    needle.lineCapStyle = .round
    NSColor.white.setStroke()
    needle.stroke()

    // Hub.
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: c.x - 44, y: c.y - 44, width: 88, height: 88)).fill()
    color(0x3A4ED6).setFill()
    NSBezierPath(ovalIn: NSRect(x: c.x - 18, y: c.y - 18, width: 36, height: 36)).fill()
}

// MARK: - Icon 2: concentric progress rings

func icon2() {
    drawBackground(top: 0xFF8A4C, bottom: 0xF5512E)  // coral -> orange-red
    func ring(radius r: CGFloat, value: CGFloat, width: CGFloat) {
        // Track ring (full circle).
        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: r, startAngle: 0, endAngle: 360, clockwise: false)
        track.lineWidth = width
        NSColor.white.withAlphaComponent(0.25).setStroke()
        track.stroke()
        // Progress arc from top, clockwise.
        let endA = 90 - value * 360
        arc(center: center, radius: r, from: 90, to: endA, width: width,
            stroke: NSColor.white.withAlphaComponent(0.97))
    }
    ring(radius: 300, value: 0.72, width: 70)  // outer = 5-hour window
    ring(radius: 198, value: 0.48, width: 70)  // inner = weekly window
    // Center dot.
    NSColor.white.withAlphaComponent(0.97).setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - 46, y: center.y - 46, width: 92, height: 92)).fill()
    color(0xF5512E).setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - 20, y: center.y - 20, width: 40, height: 40)).fill()
}

// MARK: - Icon 3: ascending bar meter

func icon3() {
    drawBackground(top: 0x16C79A, bottom: 0x0E8F75)  // teal/green
    let bars = 5
    let barW: CGFloat = 96
    let gap: CGFloat = 40
    let totalW = CGFloat(bars) * barW + CGFloat(bars - 1) * gap
    let x0 = center.x - totalW / 2
    let baseY: CGFloat = 300
    let maxH: CGFloat = 440
    for i in 0..<bars {
        let frac = CGFloat(i + 1) / CGFloat(bars)
        let h = maxH * frac
        let x = x0 + CGFloat(i) * (barW + gap)
        let rect = NSRect(x: x, y: baseY, width: barW, height: h)
        let path = NSBezierPath(roundedRect: rect, xRadius: 30, yRadius: 30)
        // Last bar dim = "remaining capacity"; others bright.
        let alpha: CGFloat = i >= bars - 1 ? 0.34 : 0.96
        NSColor.white.withAlphaComponent(alpha).setFill()
        path.fill()
    }
    // Baseline.
    let base = NSBezierPath(roundedRect: NSRect(x: x0 - 8, y: baseY - 34, width: totalW + 16, height: 20),
                            xRadius: 10, yRadius: 10)
    NSColor.white.withAlphaComponent(0.85).setFill()
    base.fill()
}

render("icon1-gauge.png", icon1)
render("icon2-rings.png", icon2)
render("icon3-bars.png", icon3)
