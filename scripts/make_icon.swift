import AppKit
import Foundation

let destination = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
    NSColor(calibratedRed: 0.055, green: 0.07, blue: 0.075, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 904, height: 904), xRadius: 205, yRadius: 205).fill()
    let accent = NSColor(calibratedRed: 0.73, green: 0.91, blue: 0.58, alpha: 1)
    for i in 0..<6 {
        accent.withAlphaComponent(0.22).setStroke()
        let path = NSBezierPath(); path.lineWidth = 6
        path.move(to: NSPoint(x: 215, y: 300 + i * 85)); path.line(to: NSPoint(x: 810, y: 300 + i * 85)); path.stroke()
    }
    accent.setStroke()
    let path = NSBezierPath(); path.lineWidth = 47; path.lineCapStyle = .round; path.lineJoinStyle = .round
    path.move(to: NSPoint(x: 280, y: 385)); path.line(to: NSPoint(x: 405, y: 385)); path.line(to: NSPoint(x: 490, y: 640)); path.line(to: NSPoint(x: 575, y: 470)); path.line(to: NSPoint(x: 745, y: 470)); path.stroke()
    for point in [NSPoint(x: 280, y: 385), NSPoint(x: 490, y: 640), NSPoint(x: 745, y: 470)] {
        accent.setFill(); NSBezierPath(ovalIn: NSRect(x: point.x - 33, y: point.y - 33, width: 66, height: 66)).fill()
    }
    image.unlockFocus()
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let data = rep.representation(using: .png, properties: [:])!
    if size <= 512 { try data.write(to: destination.appendingPathComponent("icon_\(size)x\(size).png")) }
    if size >= 32 { try data.write(to: destination.appendingPathComponent("icon_\(size / 2)x\(size / 2)@2x.png")) }
}
