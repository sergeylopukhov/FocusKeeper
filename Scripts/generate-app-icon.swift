import AppKit
import Foundation

let outputURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "dist/AppIcon.icns")
let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceURL = rootURL.appendingPathComponent("Assets/AppIconSource.png")
let fileManager = FileManager.default
let temporaryDirectory = fileManager.temporaryDirectory
    .appendingPathComponent("FocusKeeper-\(UUID().uuidString).iconset", isDirectory: true)

guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    throw NSError(
        domain: "FocusKeeperIcon",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Could not read \(sourceURL.path)."]
    )
}

try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
defer {
    try? fileManager.removeItem(at: temporaryDirectory)
}

func writePNG(size: Int, filename: String) throws {
    let targetSize = NSSize(width: size, height: size)
    let resized = NSImage(size: targetSize)

    resized.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    sourceImage.draw(
        in: NSRect(origin: .zero, size: targetSize),
        from: NSRect(origin: .zero, size: sourceImage.size),
        operation: .copy,
        fraction: 1
    )
    resized.unlockFocus()

    guard
        let tiffData = resized.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData),
        let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(
            domain: "FocusKeeperIcon",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Could not render icon size \(size)."]
        )
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
    throw NSError(
        domain: "FocusKeeperIcon",
        code: Int(process.terminationStatus),
        userInfo: [NSLocalizedDescriptionKey: "iconutil failed."]
    )
}

print("Created \(outputURL.path)")
