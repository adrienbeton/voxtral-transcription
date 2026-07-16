// Generates assets/icon-1024.png for the Voxtral app icon.
// Run with: swift scripts/make-icon.swift

import AppKit
import CoreGraphics

let canvasSize = 1024
let inset: CGFloat = 100
let contentRect = CGRect(x: inset, y: inset, width: 1024 - inset * 2, height: 1024 - inset * 2)
let cornerRadius: CGFloat = 185

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: canvasSize,
    height: canvasSize,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("Could not create CGContext")
}

// Rounded-rect clip ("squircle").
let path = CGPath(roundedRect: contentRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
ctx.addPath(path)
ctx.clip()

// Vertical gradient background: deep indigo top -> vivid violet-blue bottom.
let topColor = CGColor(red: 0x1E / 255.0, green: 0x1B / 255.0, blue: 0x4B / 255.0, alpha: 1)
let bottomColor = CGColor(red: 0x43 / 255.0, green: 0x38 / 255.0, blue: 0xCA / 255.0, alpha: 1)
let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [topColor, bottomColor] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: contentRect.midX, y: contentRect.maxY),
    end: CGPoint(x: contentRect.midX, y: contentRect.minY),
    options: []
)

// Subtle darker inner edge for depth.
ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.18))
ctx.setLineWidth(6)
ctx.addPath(path)
ctx.strokePath()

// Subtle top highlight.
let highlightGradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.10),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
    ] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(
    highlightGradient,
    start: CGPoint(x: contentRect.midX, y: contentRect.maxY),
    end: CGPoint(x: contentRect.midX, y: contentRect.maxY - contentRect.height * 0.35),
    options: []
)

// Waveform motif: vertical rounded-capsule bars, symmetric-ish heights,
// split into amber (left, speaker A) and white (right, speaker B) with a center gap.
let barHeights: [CGFloat] = [
    0.30, 0.48, 0.68, 0.42, 0.85, 0.58, 0.36,
    0.36, 0.58, 0.85, 0.42, 0.68, 0.48, 0.30,
]
let barCount = barHeights.count
let barWidth: CGFloat = 34
let gap: CGFloat = 22
let centerGap: CGFloat = 28
let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 2) * gap + centerGap
let startX = contentRect.midX - totalWidth / 2
let maxBarHeight = contentRect.height * 0.62
let centerY = contentRect.midY

let amber = CGColor(red: 0xF5 / 255.0, green: 0x9E / 255.0, blue: 0x0B / 255.0, alpha: 1)
let white = CGColor(red: 0xFA / 255.0, green: 0xFA / 255.0, blue: 0xFA / 255.0, alpha: 1)

for (index, heightFraction) in barHeights.enumerated() {
    let barHeight = max(barWidth, maxBarHeight * heightFraction)
    let extraGap = index >= barCount / 2 ? (centerGap - gap) : 0
    let x = startX + CGFloat(index) * (barWidth + gap) + extraGap
    let barRect = CGRect(x: x, y: centerY - barHeight / 2, width: barWidth, height: barHeight)
    let barPath = CGPath(roundedRect: barRect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil)
    ctx.addPath(barPath)
    ctx.setFillColor(index < barCount / 2 ? amber : white)
    ctx.fillPath()
}

guard let image = ctx.makeImage() else {
    fatalError("Could not create CGImage")
}

let bitmapRep = NSBitmapImageRep(cgImage: image)
guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
    fatalError("Could not create PNG data")
}

let outputURL = URL(fileURLWithPath: "assets/icon-1024.png")
try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try pngData.write(to: outputURL)
print("Wrote \(outputURL.path)")
