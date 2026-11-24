// Draws the app icon: a battery filled to 80% on a dark rounded square.
//   swift scripts/make-icon.swift <out.png>
import AppKit

let side: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
  // Apple's macOS grid: an 824 pt rounded square centred in a 1024 canvas.
  let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
  let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

  NSGraphicsContext.saveGraphicsState()
  let shadow = NSShadow()
  shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
  shadow.shadowBlurRadius = 24
  shadow.shadowOffset = NSSize(width: 0, height: -10)
  shadow.set()
  NSColor.black.setFill()
  tilePath.fill()
  NSGraphicsContext.restoreGraphicsState()

  NSGradient(colors: [
    NSColor(srgbRed: 0.17, green: 0.18, blue: 0.20, alpha: 1),
    NSColor(srgbRed: 0.06, green: 0.07, blue: 0.08, alpha: 1),
  ])!.draw(in: tilePath, angle: -90)

  // Battery body and cap.
  let body = NSRect(x: 222, y: 382, width: 540, height: 260)
  let outline = NSBezierPath(roundedRect: body, xRadius: 64, yRadius: 64)
  outline.lineWidth = 30
  NSColor.white.withAlphaComponent(0.92).setStroke()
  outline.stroke()
  NSColor.white.withAlphaComponent(0.92).setFill()
  NSBezierPath(roundedRect: NSRect(x: 780, y: 462, width: 34, height: 100), xRadius: 17, yRadius: 17).fill()

  // Fill to 80% of the inner width.
  let inset: CGFloat = 38
  let inner = body.insetBy(dx: inset, dy: inset)
  let fill = NSRect(x: inner.minX, y: inner.minY, width: inner.width * 0.8, height: inner.height)
  NSGradient(colors: [
    NSColor(srgbRed: 0.42, green: 0.93, blue: 0.62, alpha: 1),
    NSColor(srgbRed: 0.12, green: 0.75, blue: 0.47, alpha: 1),
  ])!.draw(in: NSBezierPath(roundedRect: fill, xRadius: 30, yRadius: 30), angle: -90)
  return true
}

let rep = NSBitmapImageRep(
  bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side), bitsPerSample: 8,
  samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
