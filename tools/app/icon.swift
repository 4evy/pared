import AppKit

// Render the same vector artwork for the app and optional PNG export paths
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
  NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
}

func monogram() -> NSBezierPath {
  let path = NSBezierPath()
  path.windingRule = .evenOdd
  path.move(to: NSPoint(x: 318, y: 266))
  path.line(to: NSPoint(x: 426, y: 266))
  path.line(to: NSPoint(x: 426, y: 466))
  path.line(to: NSPoint(x: 542, y: 466))
  path.curve(
    to: NSPoint(x: 730, y: 610),
    controlPoint1: NSPoint(x: 659, y: 466),
    controlPoint2: NSPoint(x: 730, y: 514))
  path.curve(
    to: NSPoint(x: 542, y: 754),
    controlPoint1: NSPoint(x: 730, y: 706),
    controlPoint2: NSPoint(x: 659, y: 754))
  path.line(to: NSPoint(x: 318, y: 754))
  path.close()

  path.move(to: NSPoint(x: 426, y: 562))
  path.line(to: NSPoint(x: 536, y: 562))
  path.curve(
    to: NSPoint(x: 620, y: 610),
    controlPoint1: NSPoint(x: 593, y: 562),
    controlPoint2: NSPoint(x: 620, y: 575))
  path.curve(
    to: NSPoint(x: 536, y: 658),
    controlPoint1: NSPoint(x: 620, y: 645),
    controlPoint2: NSPoint(x: 593, y: 658))
  path.line(to: NSPoint(x: 426, y: 658))
  path.close()
  return path
}

func render(pixels: Int) throws -> Data {
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
    starting: color(0.23, 0.065, 0.15),
    ending: color(0.43, 0.11, 0.26))!
    .draw(in: body, angle: 90)

  // A quiet rim keeps the dark tile visible against dark desktop surfaces
  NSColor.white.withAlphaComponent(0.12).setStroke()
  body.lineWidth = 2
  body.stroke()

  let mark = monogram()
  let retained = NSBezierPath()
  retained.move(to: NSPoint(x: 0, y: 0))
  retained.line(to: NSPoint(x: 1024, y: 0))
  retained.line(to: NSPoint(x: 1024, y: 775))
  retained.line(to: NSPoint(x: 0, y: 630))
  retained.close()
  NSGraphicsContext.saveGraphicsState()
  retained.addClip()
  let shadow = NSShadow()
  shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
  shadow.shadowOffset = NSSize(width: 0, height: -10)
  shadow.shadowBlurRadius = 14
  shadow.set()
  NSGradient(starting: color(0.96, 0.72, 0.82), ending: color(1.0, 0.93, 0.97))!
    .draw(in: mark, angle: 90)
  NSGraphicsContext.restoreGraphicsState()

  // Keep at least a pixel of separation when the mark appears in Finder lists
  NSGraphicsContext.saveGraphicsState()
  let lift = NSAffineTransform()
  lift.translateX(by: 22, yBy: max(32, 1024 / CGFloat(pixels) + 4))
  lift.concat()
  let removed = NSBezierPath()
  removed.move(to: NSPoint(x: 0, y: 630))
  removed.line(to: NSPoint(x: 1024, y: 775))
  removed.line(to: NSPoint(x: 1024, y: 1024))
  removed.line(to: NSPoint(x: 0, y: 1024))
  removed.close()
  removed.addClip()
  NSGradient(starting: color(0.89, 0.31, 0.55), ending: color(1.0, 0.65, 0.80))!
    .draw(in: mark, angle: 90)
  NSGraphicsContext.restoreGraphicsState()

  NSGraphicsContext.restoreGraphicsState()
  return bitmap.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let suffix = scale == 2 ? "@2x" : ""
    let url = destination.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
    try render(pixels: size * scale).write(to: url)
  }
}

if CommandLine.arguments.count > 2 {
  let png = try render(pixels: 256)
  for path in CommandLine.arguments.dropFirst(2) {
    try png.write(to: URL(fileURLWithPath: path))
  }
}
