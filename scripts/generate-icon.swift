#!/usr/bin/env swift
//
//  generate-icon.swift
//  SmartFan
//
//  Builds the app icon from the logo master in assets/logo/.
//
//  The mark is keyed off its white background and placed on a tile this script draws, rather
//  than taking a finished tile from the artwork: an image model cannot produce an accurate
//  corner radius or Apple's margins, and everything about the geometry is then in one place.
//
//  Grid, from Apple's macOS app icon template:
//    · canvas 1024, tile inset to 824 (100px of transparent margin on each side)
//    · tile corner radius 185 (22.4% of the tile)
//    · a soft shadow under the tile, so it sits beside system icons rather than looking flat
//
//  Writes SmartFan.iconset (10 PNGs, the input to `iconutil -c icns`) and a few previews in
//  assets/logo/preview/ for review — including a blown-up 16px, which is the size an app icon
//  is most often wrong at.
//
//  Run:  swift scripts/generate-icon.swift          (previews + iconset)
//        scripts/setup.sh icon                      (…then iconutil → SmartFan.icns)
//

import AppKit

// MARK: - Input

/// Optional `--master <png> --preview <dir>` so a candidate mark can be rendered and looked at
/// without touching the shipped one or the default preview directory.
func argument(_ name: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: name),
          index + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[index + 1]
}

var masterPath = argument("--master") ?? "assets/logo/smart-fan-mark.png"
/// Small sizes come from a simplified master when one is given: a mark with this much detail
/// cannot survive 16 px (measured: its typical stroke is 6–7 % of its width, i.e. 0.6 px at
/// 16 px), and shrinking is not the same as simplifying. Below this pixel size the simplified
/// master is used; above it, the detailed one. Apple's own icons ship the same split.
let smallMasterPath = argument("--small-master")
let smallMasterMaxPixels = 64
let iconsetPath = argument("--iconset") ?? "SmartFan.iconset"
let previewPath = argument("--preview") ?? "assets/logo/preview"

/// How much of the tile's width the mark takes at its longest side. Three previews are
/// written at the values around this one so the size can be judged rather than guessed.
let markFraction: CGFloat = 0.64
let previewFractions: [CGFloat] = [0.56, 0.64, 0.72]

/// Apple's grid, as fractions of the canvas and of the tile.
let tileFraction: CGFloat = 824.0 / 1024.0
let cornerRadiusFraction: CGFloat = 185.0 / 824.0

// MARK: - The mark, with its background keyed out

/// The mark as an image with transparency, so the tile colour shows through its gaps.
///
/// The master is drawn on plain white. A pixel's alpha is how far it is from that white, so
/// the antialiased edge keeps its softness instead of turning into a hard cut-out. Pixels
/// that are *light but not white* would fade, which is why a replacement master must not
/// contain white details inside the mark — only background.
func loadMark() -> CGImage {
    guard let source = NSImage(contentsOfFile: masterPath),
          let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fatalError("找不到母版 \(masterPath)")
    }
    let width = cg.width, height = cg.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(data: &pixels, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("无法建立像素缓冲")
    }
    context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

    // The background is whatever the corners are, not an assumed white.
    let corner = (r: Float(pixels[0]), g: Float(pixels[1]), b: Float(pixels[2]))
    for index in stride(from: 0, to: pixels.count, by: 4) {
        let r = Float(pixels[index]), g = Float(pixels[index + 1]), b = Float(pixels[index + 2])
        // 1 when the pixel matches the background, 0 when it is clearly ink.
        let distance = max(abs(r - corner.r), max(abs(g - corner.g), abs(b - corner.b)))
        let coverage = min(1, max(0, distance / 48))
        let alpha = UInt8((coverage * 255).rounded())
        // Un-premultiply, or the keyed copy would darken as alpha falls.
        pixels[index] = UInt8(min(255, Float(pixels[index]) / max(coverage, 0.004)))
        pixels[index + 1] = UInt8(min(255, Float(pixels[index + 1]) / max(coverage, 0.004)))
        pixels[index + 2] = UInt8(min(255, Float(pixels[index + 2]) / max(coverage, 0.004)))
        pixels[index + 3] = alpha
    }
    guard let keyed = context.makeImage() else { fatalError("无法生成透明母版") }
    return keyed
}

// MARK: - The icon

/// One icon at one pixel size: shadow, tile, then the mark centred on it.
func renderIcon(px: Int, mark: CGImage, fraction: CGFloat = markFraction) -> NSImage {
    let side = CGFloat(px)
    let image = NSImage(size: NSSize(width: side, height: side))
    image.lockFocus()
    defer { image.unlockFocus() }

    let tileSide = side * tileFraction
    let tile = NSRect(x: (side - tileSide) / 2, y: (side - tileSide) / 2,
                      width: tileSide, height: tileSide)
    let path = NSBezierPath(roundedRect: tile,
                            xRadius: tileSide * cornerRadiusFraction,
                            yRadius: tileSide * cornerRadiusFraction)

    // The tile: a near-white surface with the lightest of vertical gradients, so it does not
    // read as a flat swatch at large sizes.
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.28)
    shadow.shadowBlurRadius = side * 0.022
    shadow.shadowOffset = NSSize(width: 0, height: -side * 0.012)
    shadow.set()
    NSGradient(colors: [NSColor(white: 1.0, alpha: 1),
                        NSColor(white: 0.93, alpha: 1)])?.draw(in: path, angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()

    // A hairline edge keeps the tile's boundary legible against a white background.
    NSColor(white: 0, alpha: 0.06).setStroke()
    path.lineWidth = max(1, side * 0.002)
    path.stroke()

    // The mark, centred, longest side at `fraction` of the tile.
    let markSide = tileSide * fraction
    let scale = min(markSide / CGFloat(mark.width), markSide / CGFloat(mark.height))
    let size = NSSize(width: CGFloat(mark.width) * scale, height: CGFloat(mark.height) * scale)
    let rect = NSRect(x: (side - size.width) / 2, y: (side - size.height) / 2,
                      width: size.width, height: size.height)
    NSGraphicsContext.current?.cgContext.draw(
        mark, in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height))

    return image
}

func savePNG(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return }
    try! png.write(to: URL(fileURLWithPath: path))
}

// MARK: - Build

let mark = loadMark()
let smallMark = smallMasterPath.map { path -> CGImage in
    // loadMark() reads `masterPath`; borrow it for a second file by swapping the variable.
    let saved = masterPath
    masterPath = path
    let image = loadMark()
    masterPath = saved
    return image
}

try? FileManager.default.removeItem(atPath: iconsetPath)
try! FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)
/// The mark to draw at a given pixel size: the simplified one below the split, the detailed
/// one above it.
func markFor(pixels: Int) -> CGImage {
    (pixels <= smallMasterMaxPixels ? smallMark : nil) ?? mark
}
for size in [16, 32, 128, 256, 512] {
    savePNG(renderIcon(px: size, mark: markFor(pixels: size)),
            to: "\(iconsetPath)/icon_\(size)x\(size).png")
    savePNG(renderIcon(px: size * 2, mark: markFor(pixels: size * 2)),
            to: "\(iconsetPath)/icon_\(size)x\(size)@2x.png")
}
print("已生成 \(iconsetPath)（10 个尺寸）")

// Previews: the mark at three sizes, plus what 16px actually looks like, magnified.
try? FileManager.default.removeItem(atPath: previewPath)
try! FileManager.default.createDirectory(atPath: previewPath, withIntermediateDirectories: true)
for fraction in previewFractions {
    let name = String(format: "%.0f", fraction * 100)
    savePNG(renderIcon(px: 512, mark: mark, fraction: fraction), to: "\(previewPath)/mark-\(name).png")
}
for size in [16, 32, 64] {
    let small = renderIcon(px: size, mark: mark)
    // Nearest-neighbour, so the pixels are visible rather than smoothed away: this is the
    // view that shows whether the mark survives at 16pt.
    guard let tiff = small.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { continue }
    let zoom = NSImage(size: NSSize(width: size * 12, height: size * 12))
    zoom.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .none
    rep.draw(in: NSRect(x: 0, y: 0, width: size * 12, height: size * 12))
    zoom.unlockFocus()
    savePNG(zoom, to: "\(previewPath)/zoom-\(size)px.png")
}
print("已生成预览 \(previewPath)/ —— mark-56/64/72.png（三种图形大小）与 zoom-16/32/64px.png（放大看小尺寸）")
print("确认外观后运行 scripts/setup.sh icon 生成 SmartFan.icns")
