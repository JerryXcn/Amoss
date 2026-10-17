import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[1])
func icon(size: Int, mirror: Bool) -> Data {
    let accent = mirror ? NSColor(calibratedRed: 0.48, green: 0.30, blue: 0.92, alpha: 1) : NSColor.systemBlue
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let base = NSBezierPath(roundedRect: NSRect(x: 56, y: 56, width: 912, height: 912), xRadius: 210, yRadius: 210)
    context.setShadow(offset: CGSize(width: 0, height: -14), blur: 26, color: NSColor.black.withAlphaComponent(0.16).cgColor)
    accent.setFill(); base.fill()
    context.setShadow(offset: .zero, blur: 0)
    let top = mirror ? NSColor(calibratedRed: 0.64, green: 0.46, blue: 1, alpha: 1) : NSColor(calibratedRed: 0.10, green: 0.55, blue: 1, alpha: 1)
    let bottom = mirror ? NSColor(calibratedRed: 0.36, green: 0.20, blue: 0.78, alpha: 1) : NSColor(calibratedRed: 0.02, green: 0.30, blue: 0.88, alpha: 1)
    NSGradient(starting: top, ending: bottom)!.draw(in: base, angle: -75)
    let rear = NSBezierPath(roundedRect: NSRect(x: 255, y: 308, width: 292, height: 454), xRadius: 49, yRadius: 49)
    NSColor.white.withAlphaComponent(0.30).setFill(); rear.fill()
    NSColor.white.withAlphaComponent(0.65).setStroke(); rear.lineWidth = 12; rear.stroke()
    let front = NSBezierPath(roundedRect: NSRect(x: 441, y: 245, width: 292, height: 454), xRadius: 49, yRadius: 49)
    context.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: NSColor.black.withAlphaComponent(0.13).cgColor)
    NSColor.white.setFill(); front.fill()
    context.setShadow(offset: .zero, blur: 0)
    let screen = NSBezierPath(roundedRect: NSRect(x: 459, y: 264, width: 256, height: 415), xRadius: 34, yRadius: 34)
    (mirror ? NSColor(calibratedRed: 0.95, green: 0.92, blue: 1, alpha: 1) : NSColor(calibratedRed: 0.90, green: 0.95, blue: 1, alpha: 1)).setFill(); screen.fill()
    let gesture = NSBezierPath(roundedRect: NSRect(x: 548, y: 280, width: 78, height: 8), xRadius: 4, yRadius: 4)
    accent.withAlphaComponent(0.65).setFill(); gesture.fill()
    let stroke = NSBezierPath()
    stroke.move(to: NSPoint(x: 511, y: 390)); stroke.line(to: NSPoint(x: 586, y: 558)); stroke.line(to: NSPoint(x: 661, y: 390))
    stroke.move(to: NSPoint(x: 541, y: 450)); stroke.line(to: NSPoint(x: 632, y: 450))
    stroke.lineWidth = 25; stroke.lineCapStyle = .round; stroke.lineJoinStyle = .round
    accent.setStroke(); stroke.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for mirror in [false, true] {
    let iconset = root.appendingPathComponent(mirror ? "build/MirrorIcon.iconset" : "build/AppIcon.iconset")
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    for size in [16, 32, 128, 256, 512] {
        try icon(size: size, mirror: mirror).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
        try icon(size: size * 2, mirror: mirror).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
    }
}
