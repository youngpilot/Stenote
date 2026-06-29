#!/usr/bin/env swift

import AppKit

let width = 1280
let height = 640
let iconSize = 256
let projectDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

// Load the 512@2x icon (1024px)
let iconPath = projectDir.appendingPathComponent("Steneo/Assets.xcassets/AppIcon.appiconset/icon_512_512_2x.png")
guard let iconImage = NSImage(contentsOf: iconPath) else {
    fatalError("Could not load icon from \(iconPath.path)")
}

// Create the feature image
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width, pixelsHigh: height,
    bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ctx

// Dark background gradient
let bgRect = NSRect(x: 0, y: 0, width: width, height: height)
let gradient = NSGradient(colors: [
    NSColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0),
    NSColor(red: 0.12, green: 0.12, blue: 0.15, alpha: 1.0)
])!
gradient.draw(in: bgRect, angle: 90)

// Draw icon centered, shifted up to make room for text
let iconX = CGFloat(width - iconSize) / 2
let iconY = CGFloat(height - iconSize) / 2 + 40
let iconRect = NSRect(x: iconX, y: iconY, width: CGFloat(iconSize), height: CGFloat(iconSize))
iconImage.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0)

// Draw "Steneo" text below icon
let textAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 48, weight: .semibold),
    .foregroundColor: NSColor.white
]
let text = "Steneo" as NSString
let textSize = text.size(withAttributes: textAttrs)
let textX = CGFloat(width) / 2 - textSize.width / 2
let textY = iconY - textSize.height - 20
text.draw(at: NSPoint(x: textX, y: textY), withAttributes: textAttrs)

// Draw subtitle
let subAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 20, weight: .regular),
    .foregroundColor: NSColor(white: 0.6, alpha: 1.0)
]
let subtitle = "Voice-to-text for macOS" as NSString
let subSize = subtitle.size(withAttributes: subAttrs)
let subX = CGFloat(width) / 2 - subSize.width / 2
let subY = textY - subSize.height - 8
subtitle.draw(at: NSPoint(x: subX, y: subY), withAttributes: subAttrs)

NSGraphicsContext.restoreGraphicsState()

// Save as PNG
let outputPath = projectDir.appendingPathComponent("assets/feature.png")
guard let pngData = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else {
    fatalError("Could not create PNG")
}
try! pngData.write(to: outputPath)
print("Feature image saved to \(outputPath.path)")
