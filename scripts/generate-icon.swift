#!/usr/bin/env swift

import AppKit
import CoreGraphics

let iconDir = "../Steneo/Assets.xcassets/AppIcon.appiconset"

let sizes: [(size: String, scale: String, px: Int)] = [
    ("16x16",   "1x", 16),
    ("16x16",   "2x", 32),
    ("32x32",   "1x", 32),
    ("32x32",   "2x", 64),
    ("128x128", "1x", 128),
    ("128x128", "2x", 256),
    ("256x256", "1x", 256),
    ("256x256", "2x", 512),
    ("512x512", "1x", 512),
    ("512x512", "2x", 1024),
]

// Same Solar mic SVG used in the menubar (from SteneoApp.swift)
let micSVG = """
<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 24 24"><path fill="white" d="M12 2a5.75 5.75 0 0 0-5.75 5.75v3a5.75 5.75 0 0 0 11.452.75H13a.75.75 0 0 1 0-1.5h4.75V8.5H13A.75.75 0 0 1 13 7h4.701A5.75 5.75 0 0 0 12 2"/><path fill="white" fill-rule="evenodd" d="M4 9a.75.75 0 0 1 .75.75v1a7.25 7.25 0 1 0 14.5 0v-1a.75.75 0 0 1 1.5 0v1a8.75 8.75 0 0 1-8 8.718v2.282a.75.75 0 0 1-1.5 0v-2.282a8.75 8.75 0 0 1-8-8.718v-1A.75.75 0 0 1 4 9" clip-rule="evenodd"/></svg>
"""

func drawIcon(size: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    guard let context = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let s = CGFloat(size)
    let rect = CGRect(x: 0, y: 0, width: s, height: s)

    // --- Background: rounded rect with gradient ---
    let cornerRadius = s * 0.22
    let bgPath = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradientColors = [
        CGColor(red: 0.22, green: 0.08, blue: 0.52, alpha: 1.0),
        CGColor(red: 0.18, green: 0.38, blue: 0.82, alpha: 1.0),
        CGColor(red: 0.25, green: 0.55, blue: 0.90, alpha: 1.0),
    ] as CFArray
    let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: [0.0, 0.6, 1.0])!

    context.saveGState()
    context.addPath(bgPath)
    context.clip()
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])
    context.restoreGState()

    // --- Render SVG mic icon centered with padding ---
    let iconSize = Int(s * 0.65)
    let svgString = micSVG
        .replacingOccurrences(of: "{size}", with: "\(iconSize)")

    if let svgData = svgString.data(using: .utf8),
       let svgImage = NSImage(data: svgData) {
        let padding = (s - CGFloat(iconSize)) / 2
        svgImage.draw(in: CGRect(x: padding, y: padding, width: CGFloat(iconSize), height: CGFloat(iconSize)),
                      from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    image.unlockFocus()
    return image
}

// Generate all sizes
var images: [[String: String]] = []

for entry in sizes {
    let image = drawIcon(size: entry.px)
    let filename = "icon_\(entry.size.replacingOccurrences(of: "x", with: "_"))_\(entry.scale).png"
    let filepath = "\(iconDir)/\(filename)"

    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to generate \(filename)")
        continue
    }

    try! pngData.write(to: URL(fileURLWithPath: filepath))
    print("Generated \(filename) (\(entry.px)x\(entry.px))")

    images.append([
        "filename": filename,
        "idiom": "mac",
        "scale": entry.scale,
        "size": entry.size,
    ])
}

// Write Contents.json
let contents: [String: Any] = [
    "images": images.map { img in
        return [
            "filename": img["filename"]!,
            "idiom": img["idiom"]!,
            "scale": img["scale"]!,
            "size": img["size"]!,
        ]
    },
    "info": [
        "author": "xcode",
        "version": 1,
    ],
]

let jsonData = try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try! jsonData.write(to: URL(fileURLWithPath: "\(iconDir)/Contents.json"))
print("Updated Contents.json")
