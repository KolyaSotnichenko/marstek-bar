#!/usr/bin/env swift
// Renders the MarstekBar app icon into App/Assets.xcassets/AppIcon.appiconset.
// Usage: swift scripts/make-icon.swift
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "App/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Draws the icon on a 1024-point canvas; smaller sizes are the same drawing scaled.
func drawIcon(in ctx: CGContext) {
    // macOS icon grid: the tile is 824 pt inside a 1024 canvas, corner radius ~185.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Drop shadow under the tile.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(tilePath)
    ctx.setFillColor(color(0x0E1A33))
    ctx.fillPath()
    ctx.restoreGState()

    // Night-blue to teal background.
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let background = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                colors: [color(0x13254A), color(0x1C5D72)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // Soft highlight in the upper half.
    let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: [color(0xFFFFFF, 0.14), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 860), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 860), endRadius: 520, options: [])
    ctx.restoreGState()

    // Battery body.
    let body = CGRect(x: 262, y: 352, width: 450, height: 320)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 70, cornerHeight: 70, transform: nil)
    ctx.addPath(bodyPath)
    ctx.setStrokeColor(color(0xFFFFFF))
    ctx.setLineWidth(34)
    ctx.strokePath()

    // Terminal cap.
    let cap = CGRect(x: 730, y: 452, width: 48, height: 120)
    ctx.addPath(CGPath(roundedRect: cap, cornerWidth: 22, cornerHeight: 22, transform: nil))
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath()

    // Charge level: green fill, about two thirds.
    let fill = body.insetBy(dx: 44, dy: 44)
    let level = CGRect(x: fill.minX, y: fill.minY, width: fill.width * 0.68, height: fill.height)
    let levelPath = CGPath(roundedRect: level, cornerWidth: 30, cornerHeight: 30, transform: nil)
    ctx.saveGState()
    ctx.addPath(levelPath)
    ctx.clip()
    let green = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: [color(0x7CF2A4), color(0x2FC46B)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(green, start: CGPoint(x: 0, y: level.maxY), end: CGPoint(x: 0, y: level.minY), options: [])
    ctx.restoreGState()

    // Lightning bolt across the battery, outlined in the background colour so it reads at 16 px.
    let bolt = CGMutablePath()
    bolt.move(to: CGPoint(x: 540, y: 760))
    bolt.addLine(to: CGPoint(x: 400, y: 498))
    bolt.addLine(to: CGPoint(x: 506, y: 498))
    bolt.addLine(to: CGPoint(x: 462, y: 268))
    bolt.addLine(to: CGPoint(x: 624, y: 548))
    bolt.addLine(to: CGPoint(x: 514, y: 548))
    bolt.closeSubpath()
    ctx.addPath(bolt)
    ctx.setLineJoin(.round)
    ctx.setLineWidth(30)
    ctx.setStrokeColor(color(0x15304F))
    ctx.strokePath()
    ctx.addPath(bolt)
    ctx.setFillColor(color(0xFFD54A))
    ctx.fillPath()
}

func png(pixels: Int) throws -> Data {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    ctx.interpolationQuality = .high
    drawIcon(in: ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

struct Slot { let size: Int; let scale: Int }
let slots = [16, 32, 128, 256, 512].flatMap { [Slot(size: $0, scale: 1), Slot(size: $0, scale: 2)] }
var images: [[String: String]] = []
for slot in slots {
    let name = "icon_\(slot.size)x\(slot.size)\(slot.scale == 2 ? "@2x" : "").png"
    try png(pixels: slot.size * slot.scale).write(to: output.appendingPathComponent(name))
    images.append(["idiom": "mac", "size": "\(slot.size)x\(slot.size)", "scale": "\(slot.scale)x", "filename": name])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appendingPathComponent("Contents.json"))
let catalog = output.deletingLastPathComponent().appendingPathComponent("Contents.json")
if !FileManager.default.fileExists(atPath: catalog.path) {
    try Data(#"{"info":{"author":"xcode","version":1}}"#.utf8).write(to: catalog)
}
print("wrote \(slots.count) icons to \(output.path)")
