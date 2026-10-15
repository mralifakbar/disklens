// Renders the app icon (a little treemap) into an .iconset folder.
// Usage: swift scripts/make-icon.swift build/AppIcon.iconset
import AppKit

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
}

let tiles: [(NSRect, NSColor, Bool)] = [
    (NSRect(x: 196, y: 196, width: 360, height: 632), color(0.47, 0.40, 0.93), false),
    (NSRect(x: 576, y: 508, width: 252, height: 320), color(0.88, 0.33, 0.58), false),
    (NSRect(x: 576, y: 196, width: 252, height: 292), color(0.20, 0.64, 0.33), true),
]

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)

    let body = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGradient(starting: color(1, 1, 1), ending: color(0.93, 0.93, 0.94))!.draw(in: body, angle: -90)
    color(0, 0, 0).withAlphaComponent(0.08).setStroke()
    body.lineWidth = 4
    body.stroke()

    for (rect, c, hatched) in tiles {
        let path = NSBezierPath(roundedRect: rect, xRadius: 34, yRadius: 34)
        c.withAlphaComponent(0.22).setFill()
        path.fill()
        if hatched {
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            let lines = NSBezierPath()
            var x = rect.minX - rect.height
            while x < rect.maxX {
                lines.move(to: NSPoint(x: x, y: rect.minY))
                lines.line(to: NSPoint(x: x + rect.height, y: rect.maxY))
                x += 36
            }
            lines.lineWidth = 10
            c.withAlphaComponent(0.55).setStroke()
            lines.stroke()
            NSGraphicsContext.restoreGraphicsState()
        }
        path.lineWidth = 10
        c.withAlphaComponent(0.85).setStroke()
        path.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
                   ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
                   ("512x512", 512), ("512x512@2x", 1024)] {
    try! render(px).write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
