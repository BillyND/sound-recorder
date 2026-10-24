// Renders the Sound Recorder app icon (sound wave with echo arcs on a vibrant
// gradient squircle) into an .iconset folder for iconutil.
// Usage: make-icon <output.iconset>

import AppKit

func drawIcon(in ctx: CGContext, pixels: CGFloat) {
    ctx.scaleBy(x: pixels / 1024, y: pixels / 1024)
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!

    // Soft drop shadow, then the gradient body.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: CGColor(gray: 0, alpha: 0.32))
    ctx.addPath(shape)
    ctx.setFillColor(CGColor(red: 0.9, green: 0.3, blue: 0.5, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let colors = [
        CGColor(red: 0.40, green: 0.32, blue: 0.98, alpha: 1),
        CGColor(red: 0.98, green: 0.30, blue: 0.52, alpha: 1),
        CGColor(red: 1.00, green: 0.63, blue: 0.30, alpha: 1),
    ] as CFArray
    let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 100, y: 924), end: CGPoint(x: 924, y: 100), options: [])
    // Glassy highlight on the upper half.
    let shine = CGGradient(colorsSpace: space, colors: [CGColor(gray: 1, alpha: 0.22), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(shine, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 480), options: [])
    ctx.restoreGState()

    let center = CGPoint(x: 512, y: 512)
    ctx.setLineCap(.round)

    // Echo arcs on both sides, fading outward.
    for (radius, alpha) in [(300.0, 0.6), (372.0, 0.32)] {
        ctx.setStrokeColor(CGColor(gray: 1, alpha: alpha))
        ctx.setLineWidth(30)
        for side in [0.0, Double.pi] {
            ctx.addArc(center: center, radius: radius, startAngle: side - 0.62, endAngle: side + 0.62, clockwise: false)
            ctx.strokePath()
        }
    }

    // The wave: rounded bars.
    let heights: [CGFloat] = [0.26, 0.5, 0.78, 1.0, 0.78, 0.5, 0.26]
    let barWidth: CGFloat = 42, gap: CGFloat = 30, maxHeight: CGFloat = 380
    let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    for (i, h) in heights.enumerated() {
        let height = maxHeight * h
        let x = center.x - totalWidth / 2 + CGFloat(i) * (barWidth + gap)
        let rect = CGRect(x: x, y: center.y - height / 2, width: barWidth, height: height)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
        ctx.fillPath()
    }
}

func png(pixels: Int) -> Data {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    drawIcon(in: ctx, pixels: CGFloat(pixels))
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon <output.iconset>\n".utf8))
    exit(1)
}
let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try png(pixels: size).write(to: folder.appendingPathComponent("icon_\(size)x\(size).png"))
    try png(pixels: size * 2).write(to: folder.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
