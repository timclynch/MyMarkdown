import AppKit
import Foundation

guard CommandLine.arguments.count > 1 else { exit(1) }
let outputRoot = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let iconset = outputRoot.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let fm = FileManager.default
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

let variants: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

for (name, pixels) in variants {
    let size = NSSize(width: pixels, height: pixels)
    let image = NSImage(size: size)
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high

    let inset = CGFloat(pixels) * 0.055
    let rect = NSRect(x: inset, y: inset, width: CGFloat(pixels) - inset * 2, height: CGFloat(pixels) - inset * 2)
    let radius = CGFloat(pixels) * 0.22
    let background = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    let gradient = NSGradient(colors: [
        NSColor(red: 0.14, green: 0.53, blue: 1.0, alpha: 1),
        NSColor(red: 0.16, green: 0.28, blue: 0.88, alpha: 1)
    ])!
    gradient.draw(in: background, angle: -55)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
    shadow.shadowOffset = NSSize(width: 0, height: -CGFloat(pixels) * 0.018)
    shadow.shadowBlurRadius = CGFloat(pixels) * 0.035
    shadow.set()

    let font = NSFont.systemFont(ofSize: CGFloat(pixels) * 0.48, weight: .heavy)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraph
    ]
    let text = NSAttributedString(string: "M", attributes: attributes)
    let textHeight = text.size().height
    let textRect = NSRect(x: 0, y: CGFloat(pixels) * 0.5 - textHeight * 0.5 - CGFloat(pixels) * 0.015, width: CGFloat(pixels), height: textHeight)
    text.draw(in: textRect)

    image.unlockFocus()
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else { exit(2) }
    try png.write(to: iconset.appendingPathComponent(name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", outputRoot.appendingPathComponent("AppIcon.icns").path]
try process.run()
process.waitUntilExit()
try? fm.removeItem(at: iconset)
exit(process.terminationStatus)
