import AppKit

// Render a small native vector mark at every size required by iconutil
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

for size in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let pixels = size * scale
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let factor = CGFloat(pixels) / 1024
    let transform = NSAffineTransform()
    transform.scale(by: factor)
    transform.concat()

    let body = NSBezierPath(
      roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896),
      xRadius: 200, yRadius: 200)
    NSGradient(
      starting: NSColor(srgbRed: 0.10, green: 0.18, blue: 0.20, alpha: 1),
      ending: NSColor(srgbRed: 0.20, green: 0.31, blue: 0.34, alpha: 1))!
      .draw(in: body, angle: 90)

    for (y, knob) in [(CGFloat(704), CGFloat(650)), (512, 374), (320, 582)] {
      let track = NSBezierPath(
        roundedRect: NSRect(x: 230, y: y - 22, width: 564, height: 44),
        xRadius: 22, yRadius: 22)
      NSColor.white.withAlphaComponent(0.42).setFill()
      track.fill()
      let active = NSBezierPath(
        roundedRect: NSRect(x: 230, y: y - 22, width: knob - 230, height: 44),
        xRadius: 22, yRadius: 22)
      NSColor(srgbRed: 0.65, green: 0.91, blue: 0.81, alpha: 1).setFill()
      active.fill()
      let circle = NSBezierPath(ovalIn: NSRect(x: knob - 58, y: y - 58, width: 116, height: 116))
      NSColor(srgbRed: 0.92, green: 0.97, blue: 0.96, alpha: 1).setFill()
      circle.fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    let suffix = scale == 2 ? "@2x" : ""
    let url = destination.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
  }
}
