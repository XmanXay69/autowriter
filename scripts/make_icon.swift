// Draws the AutoWriter app icon and writes every macOS size into the asset catalog.
// It matches Window Watcher's icon: the same dark tile and app window, but
// with lines of text and a blue typing cursor instead of the eye.
// Usage: swift scripts/make_icon.swift
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconSet = root.appendingPathComponent("App/Resources/Assets.xcassets/AppIcon.appiconset")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Rectangles are given like Window Watcher's make_icon.py (y measured from the top).
func rect(_ x: CGFloat, _ top: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
    CGRect(x: x, y: 1024 - top - height, width: width, height: height)
}

func drawIcon(size: Int) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)

    // The tile: Apple's icon grid uses an 824 px rounded square on a 1024 canvas.
    let tile = CGPath(roundedRect: rect(100, 100, 824, 824), cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: color(0x000000, 0.3))
    ctx.addPath(tile)
    ctx.setFillColor(color(0x1B1C1F))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(tile)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: space, colors: [color(0x3A3C42), color(0x1B1C1F)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    ctx.restoreGState()

    // The app window: a light outline with a title bar and three dots.
    let window = CGPath(roundedRect: rect(232, 282, 560, 440), cornerWidth: 48, cornerHeight: 48, transform: nil)
    ctx.addPath(window)
    ctx.setFillColor(color(0x26272B))
    ctx.fillPath()
    ctx.addPath(window)
    ctx.setStrokeColor(color(0xE8E8ED))
    ctx.setLineWidth(22)
    ctx.strokePath()
    ctx.move(to: CGPoint(x: 232, y: 1024 - 382))
    ctx.addLine(to: CGPoint(x: 792, y: 1024 - 382))
    ctx.strokePath()
    ctx.setFillColor(color(0xE8E8ED))
    for x in [292.0, 340.0, 388.0] {
        ctx.fillEllipse(in: CGRect(x: x - 14, y: 1024 - 332 - 14, width: 28, height: 28))
    }

    // Lines of text: the typed part is bright, the part still to come is dim,
    // and the blue cursor sits where AutoWriter is typing.
    func bar(_ x: CGFloat, _ top: CGFloat, _ width: CGFloat, _ fill: CGColor) {
        ctx.addPath(CGPath(roundedRect: rect(x, top, width, 28), cornerWidth: 14, cornerHeight: 14, transform: nil))
        ctx.setFillColor(fill)
        ctx.fillPath()
    }
    bar(296, 448, 432, color(0xE8E8ED, 0.9))
    bar(296, 512, 376, color(0xE8E8ED, 0.9))
    bar(296, 576, 216, color(0xE8E8ED, 0.9))
    bar(572, 576, 156, color(0xE8E8ED, 0.22))
    bar(296, 640, 300, color(0xE8E8ED, 0.22))
    ctx.addPath(CGPath(roundedRect: rect(530, 550, 22, 80), cornerWidth: 11, cornerHeight: 11, transform: nil))
    ctx.setFillColor(color(0x0A84FF))
    ctx.fillPath()

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)
var images: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try writePNG(drawIcon(size: size * scale), to: iconSet.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: iconSet.appendingPathComponent("Contents.json"))
try JSONSerialization.data(withJSONObject: ["info": ["author": "xcode", "version": 1]], options: .prettyPrinted)
    .write(to: iconSet.deletingLastPathComponent().appendingPathComponent("Contents.json"))
try writePNG(drawIcon(size: 1024), to: root.appendingPathComponent("icon.png"))
print("Made the app icon (App/Resources/Assets.xcassets) and icon.png")
