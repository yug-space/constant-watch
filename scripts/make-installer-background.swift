import AppKit
import Foundation

let output = CommandLine.arguments[1]
let width = 900.0, height = 600.0
let ink = NSColor(calibratedRed: 0.11, green: 0.15, blue: 0.21, alpha: 1)
let blue = NSColor(calibratedRed: 0.20, green: 0.39, blue: 0.95, alpha: 1)
let muted = NSColor(calibratedRed: 0.40, green: 0.45, blue: 0.53, alpha: 1)
for scale in [1, 2] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width) * scale, pixelsHigh: Int(height) * scale, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.white.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
    let wash = NSGradient(starting: NSColor(calibratedRed: 0.94, green: 0.97, blue: 1, alpha: 1), ending: .white)!
    wash.draw(in: NSRect(x: 0, y: 0, width: width, height: 190), angle: 90)
    func text(_ value: String, top: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor, boxHeight: CGFloat = 60) {
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        (value as NSString).draw(in: NSRect(x: 45, y: height - top - boxHeight, width: width - 90, height: boxHeight), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: paragraph])
    }
    text("C O N S T A N T   W A T C H", top: 44, size: 12, weight: .medium, color: muted)
    text("Drag Constant Watch", top: 96, size: 43, weight: .semibold, color: ink)
    text("to Applications.", top: 150, size: 43, weight: .semibold, color: blue)
    text("Your private memory is almost home.", top: 216, size: 17, weight: .regular, color: muted)
    // Directional cue between the two real Finder icons, not a simulated installer.
    func point(_ x: Double, _ y: Double) -> NSPoint { NSPoint(x: x, y: height-y) }
    let arrow = NSBezierPath(); arrow.move(to: point(375,350))
    arrow.curve(to: point(525,350), controlPoint1: point(422,382), controlPoint2: point(480,382))
    arrow.lineWidth = 3; arrow.lineCapStyle = .round; blue.setStroke(); arrow.stroke()
    let head = NSBezierPath(); head.move(to: point(506,350)); head.line(to: point(526,349)); head.line(to: point(521,368)); head.lineWidth = 3; head.lineCapStyle = .round; head.lineJoinStyle = .round; head.stroke()
    text("Then open Constant Watch from Applications.", top: 481, size: 17, weight: .medium, color: ink)
    text("Follow the welcome to enable screen access and set up your local model.", top: 510, size: 14, weight: .regular, color: muted)
    text("APPLE SILICON  ·  MACOS 14+  ·  NO ACCOUNT NEEDED", top: 560, size: 11, weight: .medium, color: muted, boxHeight: 25)
    NSGraphicsContext.restoreGraphicsState()
    let path = output + (scale == 2 ? "@2x.png" : ".png")
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
