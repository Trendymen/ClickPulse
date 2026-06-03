// 生成 1024x1024 App 图标 PNG：渐变 squircle 背景 + 白色 cursorarrow.click
// 用法：swift scripts/gen-icon.swift <输出路径.png>
import AppKit

let px = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let sz = CGFloat(px)
let inset = sz * 0.08
let rect = NSRect(x: inset, y: inset, width: sz - 2 * inset, height: sz - 2 * inset)
let radius = (sz - 2 * inset) * 0.225
let bg = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

let gradient = NSGradient(
    starting: NSColor(red: 0.35, green: 0.40, blue: 0.96, alpha: 1.0),
    ending:   NSColor(red: 0.58, green: 0.33, blue: 0.93, alpha: 1.0))!
gradient.draw(in: bg, angle: -90)

let cfg = NSImage.SymbolConfiguration(pointSize: sz * 0.40, weight: .semibold)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
if let sym = NSImage(systemSymbolName: "cursorarrow.click", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) {
    let s = sym.size
    sym.draw(in: NSRect(x: (sz - s.width) / 2, y: (sz - s.height) / 2, width: s.width, height: s.height))
}

NSGraphicsContext.restoreGraphicsState()

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: outPath))
print("icon written: \(outPath)")
