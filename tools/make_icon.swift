#!/usr/bin/env swift
import AppKit

// Renders the HoldKey app icon: green gradient squircle + white cursor symbol
// sitting on a subtle horizontal double-arrow (the "locked axis").

func render(_ size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB,
                              bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: s, height: s)
    NSGraphicsContext.saveGraphicsState()
    let nsctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = nsctx
    let cg = nsctx.cgContext

    // Background squircle with green gradient
    let pad = s * 0.06
    let bg = CGRect(x: pad, y: pad, width: s - 2*pad, height: s - 2*pad)
    let radius = bg.width * 0.2237
    let bgPath = CGPath(roundedRect: bg, cornerWidth: radius, cornerHeight: radius, transform: nil)
    cg.saveGState()
    cg.addPath(bgPath); cg.clip()
    let colors = [CGColor(red: 0.24, green: 0.86, blue: 0.56, alpha: 1),
                  CGColor(red: 0.02, green: 0.48, blue: 0.42, alpha: 1)] as CFArray
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors,
                          locations: [0, 1])!
    cg.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])
    cg.restoreGState()

    // Subtle horizontal double-arrow (the locked axis), behind the cursor
    cg.saveGState()
    let lineY = s * 0.5
    cg.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.22))
    cg.setLineWidth(s * 0.030)
    cg.setLineCap(.round); cg.setLineJoin(.round)
    let xL = s * 0.24, xR = s * 0.76, head = s * 0.05
    cg.move(to: CGPoint(x: xL, y: lineY)); cg.addLine(to: CGPoint(x: xR, y: lineY)); cg.strokePath()
    // arrowheads
    cg.move(to: CGPoint(x: xL + head, y: lineY + head)); cg.addLine(to: CGPoint(x: xL, y: lineY)); cg.addLine(to: CGPoint(x: xL + head, y: lineY - head)); cg.strokePath()
    cg.move(to: CGPoint(x: xR - head, y: lineY + head)); cg.addLine(to: CGPoint(x: xR, y: lineY)); cg.addLine(to: CGPoint(x: xR - head, y: lineY - head)); cg.strokePath()
    cg.restoreGState()

    // White cursor symbol on top, with a soft shadow for depth
    let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.44, weight: .bold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let sym = NSImage(systemSymbolName: "cursorarrow", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) {
        sym.isTemplate = false
        let sz = sym.size
        let rect = NSRect(x: (s - sz.width) / 2, y: (s - sz.height) / 2, width: sz.width, height: sz.height)
        cg.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03,
                     color: CGColor(red: 0, green: 0.15, blue: 0.10, alpha: 0.45))
        sym.draw(in: rect)
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let outDir = "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
let specs: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in specs {
    let data = render(px)
    try! data.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}
print("Wrote \(specs.count) PNGs to \(outDir)/")
