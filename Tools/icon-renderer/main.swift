import AppKit
import CoreGraphics
import Foundation

// Renders the LocalWhisper app icon as a 1024x1024 PNG.
// Usage: swift Tools/icon-renderer/main.swift <output.png>

func renderIcon(size: CGFloat) -> NSImage {
    let canvas = NSImage(size: NSSize(width: size, height: size))
    canvas.lockFocus()
    defer { canvas.unlockFocus() }

    guard let ctx = NSGraphicsContext.current?.cgContext else { return canvas }

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = size * 0.2237 // Apple HIG squircle approximation

    // Squircle clip
    let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()

    // Background gradient: deep indigo → bright blue
    let topColor = CGColor(red: 0.35, green: 0.39, blue: 1.00, alpha: 1.0)
    let bottomColor = CGColor(red: 0.10, green: 0.13, blue: 0.40, alpha: 1.0)
    let space = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(colorsSpace: space, colors: [topColor, bottomColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: size),
        end: CGPoint(x: size, y: 0),
        options: []
    )

    // Soft top highlight
    let highlight = CGGradient(
        colorsSpace: space,
        colors: [
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.18),
            CGColor(red: 1, green: 1, blue: 1, alpha: 0)
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawRadialGradient(
        highlight,
        startCenter: CGPoint(x: size * 0.3, y: size * 0.85),
        startRadius: 0,
        endCenter: CGPoint(x: size * 0.3, y: size * 0.85),
        endRadius: size * 0.55,
        options: []
    )

    // Microphone capsule centered, slight left bias to leave room for waves
    let micWidth = size * 0.30
    let micHeight = size * 0.46
    let micX = size * 0.30
    let micY = (size - micHeight) / 2 + size * 0.04
    let micRect = CGRect(x: micX, y: micY, width: micWidth, height: micHeight)
    let micRadius = micWidth / 2

    // Mic shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.012),
                  blur: size * 0.04,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35))
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.addPath(CGPath(roundedRect: micRect, cornerWidth: micRadius, cornerHeight: micRadius, transform: nil))
    ctx.fillPath()
    ctx.restoreGState()

    // Inner mic gradient
    let micGradient = CGGradient(
        colorsSpace: space,
        colors: [
            CGColor(red: 1, green: 1, blue: 1, alpha: 1),
            CGColor(red: 0.86, green: 0.90, blue: 1.0, alpha: 1)
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: micRect.insetBy(dx: size * 0.012, dy: size * 0.012),
                       cornerWidth: micRadius, cornerHeight: micRadius, transform: nil))
    ctx.clip()
    ctx.drawLinearGradient(micGradient,
                           start: CGPoint(x: micRect.midX, y: micRect.maxY),
                           end: CGPoint(x: micRect.midX, y: micRect.minY),
                           options: [])
    ctx.restoreGState()

    // Mic stand: stem + base
    let stemWidth = size * 0.04
    let stemHeight = size * 0.10
    let stemRect = CGRect(
        x: micRect.midX - stemWidth / 2,
        y: micY - stemHeight,
        width: stemWidth,
        height: stemHeight
    )
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    ctx.fill(stemRect)

    let baseWidth = micWidth * 0.9
    let baseHeight = size * 0.022
    let baseRect = CGRect(
        x: micRect.midX - baseWidth / 2,
        y: stemRect.minY - baseHeight,
        width: baseWidth,
        height: baseHeight
    )
    ctx.addPath(CGPath(roundedRect: baseRect, cornerWidth: baseHeight / 2, cornerHeight: baseHeight / 2, transform: nil))
    ctx.fillPath()

    // Sound waves on the right
    let waveCenter = CGPoint(x: micRect.maxX + size * 0.05, y: micRect.midY)
    let waveColors: [CGColor] = [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.95),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.65),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.40)
    ]
    let radii: [CGFloat] = [size * 0.10, size * 0.18, size * 0.26]
    let lineWidth = size * 0.022
    ctx.setLineWidth(lineWidth)
    ctx.setLineCap(.round)
    for (idx, radius) in radii.enumerated() {
        ctx.setStrokeColor(waveColors[idx])
        let waveRect = CGRect(x: waveCenter.x - radius, y: waveCenter.y - radius,
                              width: radius * 2, height: radius * 2)
        let arc = CGMutablePath()
        // Open arc spanning 100° (from -50° to +50° relative to right axis)
        let start = CGFloat.pi * (1.0 / -3.6) // ~ -50°
        let end = CGFloat.pi * (1.0 / 3.6)    // ~ +50°
        arc.addArc(center: waveCenter, radius: radius,
                   startAngle: start, endAngle: end, clockwise: false)
        _ = waveRect
        ctx.addPath(arc)
        ctx.strokePath()
    }

    ctx.restoreGState()
    return canvas
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "icon-renderer", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG"])
    }
    try png.write(to: url)
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("usage: icon-renderer <output.png>\n".data(using: .utf8)!)
    exit(2)
}

let outputURL = URL(fileURLWithPath: args[1])
let icon = renderIcon(size: 1024)
do {
    try writePNG(icon, to: outputURL)
    print("Wrote \(outputURL.path)")
} catch {
    FileHandle.standardError.write("error: \(error.localizedDescription)\n".data(using: .utf8)!)
    exit(1)
}
