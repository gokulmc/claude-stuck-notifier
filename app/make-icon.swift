// Draws the Nudge app icon (coral squircle + white spark) to a 1024px PNG.
// Usage: make-icon <output.png>   (no SVG tooling needed)

import AppKit

let px = 1024
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let size = CGFloat(px)
let inset: CGFloat = 96
let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let squircle = NSBezierPath(roundedRect: rect, xRadius: 210, yRadius: 210)
NSGradient(starting: NSColor(srgbRed: 0xE0 / 255.0, green: 0x8A / 255.0, blue: 0x63 / 255.0, alpha: 1),
           ending:   NSColor(srgbRed: 0xC9 / 255.0, green: 0x69 / 255.0, blue: 0x4A / 255.0, alpha: 1))!
    .draw(in: squircle, angle: -90)

let cx = size / 2, cy = size / 2
NSColor.white.setStroke()
let spark = NSBezierPath()
spark.lineWidth = 44
spark.lineCapStyle = .round
// 4 strokes => an 8-point sparkle; axes longer than the diagonals
let dirs: [(CGFloat, CGFloat, CGFloat)] = [
    (1, 0, 208), (0, 1, 208),
    (0.7071, 0.7071, 150), (0.7071, -0.7071, 150),
]
for (dx, dy, len) in dirs {
    spark.move(to: NSPoint(x: cx - dx * len, y: cy - dy * len))
    spark.line(to: NSPoint(x: cx + dx * len, y: cy + dy * len))
}
spark.stroke()

NSGraphicsContext.restoreGraphicsState()

let out = CommandLine.arguments.dropFirst().first ?? "icon-1024.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
