import AppKit
import Foundation

let outputURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "dist/AppIcon.icns")
let fileManager = FileManager.default
let temporaryDirectory = fileManager.temporaryDirectory
    .appendingPathComponent("FocusKeeper-\(UUID().uuidString).iconset", isDirectory: true)

try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
defer {
    try? fileManager.removeItem(at: temporaryDirectory)
}

let iconSize: CGFloat = 1024
let image = NSImage(size: NSSize(width: iconSize, height: iconSize))

image.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high

let bounds = NSRect(x: 0, y: 0, width: iconSize, height: iconSize)
let cornerRadius: CGFloat = 228
let backgroundPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 42, dy: 42), xRadius: cornerRadius, yRadius: cornerRadius)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
shadow.shadowOffset = NSSize(width: 0, height: -24)
shadow.shadowBlurRadius = 36
shadow.set()

NSGradient(colors: [
    NSColor(calibratedRed: 0.04, green: 0.33, blue: 0.76, alpha: 1.0),
    NSColor(calibratedRed: 0.00, green: 0.58, blue: 0.72, alpha: 1.0),
    NSColor(calibratedRed: 0.14, green: 0.68, blue: 0.45, alpha: 1.0)
])?.draw(in: backgroundPath, angle: -38)
NSGraphicsContext.restoreGraphicsState()

NSColor.white.withAlphaComponent(0.20).setStroke()
backgroundPath.lineWidth = 8
backgroundPath.stroke()

let targetCenter = CGPoint(x: 438, y: 574)

NSColor.white.withAlphaComponent(0.96).setStroke()

let outerTarget = NSBezierPath(ovalIn: NSRect(x: targetCenter.x - 190, y: targetCenter.y - 190, width: 380, height: 380))
outerTarget.lineWidth = 42
outerTarget.stroke()

let innerTarget = NSBezierPath(ovalIn: NSRect(x: targetCenter.x - 94, y: targetCenter.y - 94, width: 188, height: 188))
innerTarget.lineWidth = 34
innerTarget.stroke()

let crosshair = NSBezierPath()
crosshair.move(to: CGPoint(x: targetCenter.x, y: targetCenter.y + 252))
crosshair.line(to: CGPoint(x: targetCenter.x, y: targetCenter.y + 148))
crosshair.move(to: CGPoint(x: targetCenter.x, y: targetCenter.y - 148))
crosshair.line(to: CGPoint(x: targetCenter.x, y: targetCenter.y - 252))
crosshair.move(to: CGPoint(x: targetCenter.x - 252, y: targetCenter.y))
crosshair.line(to: CGPoint(x: targetCenter.x - 148, y: targetCenter.y))
crosshair.move(to: CGPoint(x: targetCenter.x + 148, y: targetCenter.y))
crosshair.line(to: CGPoint(x: targetCenter.x + 252, y: targetCenter.y))
crosshair.lineWidth = 32
crosshair.lineCapStyle = .round
crosshair.stroke()

NSColor.white.setFill()
NSBezierPath(ovalIn: NSRect(x: targetCenter.x - 38, y: targetCenter.y - 38, width: 76, height: 76)).fill()

let badgeRect = NSRect(x: 568, y: 248, width: 258, height: 258)
let badgePath = NSBezierPath(ovalIn: badgeRect)

NSColor.white.setFill()
NSBezierPath(ovalIn: badgeRect.insetBy(dx: -18, dy: -18)).fill()
NSColor(calibratedRed: 0.16, green: 0.78, blue: 0.36, alpha: 1.0).setFill()
badgePath.fill()

let checkPath = NSBezierPath()
checkPath.move(to: CGPoint(x: 636, y: 378))
checkPath.line(to: CGPoint(x: 684, y: 330))
checkPath.line(to: CGPoint(x: 762, y: 438))
checkPath.lineWidth = 34
checkPath.lineCapStyle = .round
checkPath.lineJoinStyle = .round
NSColor.white.setStroke()
checkPath.stroke()

image.unlockFocus()

func writePNG(size: Int, filename: String) throws {
    let targetSize = NSSize(width: size, height: size)
    let resized = NSImage(size: targetSize)
    resized.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(origin: .zero, size: targetSize), from: bounds, operation: .copy, fraction: 1)
    resized.unlockFocus()

    guard
        let tiffData = resized.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData),
        let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "FocusKeeperIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not render icon size \(size)."])
    }

    try pngData.write(to: temporaryDirectory.appendingPathComponent(filename))
}

try writePNG(size: 16, filename: "icon_16x16.png")
try writePNG(size: 32, filename: "icon_16x16@2x.png")
try writePNG(size: 32, filename: "icon_32x32.png")
try writePNG(size: 64, filename: "icon_32x32@2x.png")
try writePNG(size: 128, filename: "icon_128x128.png")
try writePNG(size: 256, filename: "icon_128x128@2x.png")
try writePNG(size: 256, filename: "icon_256x256.png")
try writePNG(size: 512, filename: "icon_256x256@2x.png")
try writePNG(size: 512, filename: "icon_512x512.png")
try writePNG(size: 1024, filename: "icon_512x512@2x.png")

try fileManager.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try? fileManager.removeItem(at: outputURL)

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = [
    "-c", "icns",
    temporaryDirectory.path,
    "-o", outputURL.path
]
try process.run()
process.waitUntilExit()

if process.terminationStatus != 0 {
    throw NSError(domain: "FocusKeeperIcon", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "iconutil failed."])
}

print("Created \(outputURL.path)")
