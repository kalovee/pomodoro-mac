// 產生 App 圖示：圓角漸層底 + 🍅
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./icon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func render(_ size: Int) -> Data? {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current else { image.unlockFocus(); return nil }
    ctx.imageInterpolation = .high

    // 圓角底：macOS 風格的內縮比例
    let inset = s * 0.085
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.2237, yRadius: s * 0.2237)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.97, green: 0.42, blue: 0.35, alpha: 1),
        NSColor(calibratedRed: 0.85, green: 0.22, blue: 0.20, alpha: 1),
    ])?.draw(in: path, angle: -90)

    // 🍅
    let glyph = "🍅" as NSString
    let font = NSFont.systemFont(ofSize: s * 0.52)
    let attrs: [NSAttributedString.Key: Any] = [.font: font]
    let bounds = glyph.size(withAttributes: attrs)
    glyph.draw(at: NSPoint(x: (s - bounds.width) / 2, y: (s - bounds.height) / 2 - s * 0.01),
               withAttributes: attrs)

    image.unlockFocus()
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return nil }
    rep.size = NSSize(width: s, height: s)
    return rep.representation(using: .png, properties: [:])
}

for (size, name) in [(16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"),
                     (128, "128x128"), (256, "128x128@2x"), (256, "256x256"),
                     (512, "256x256@2x"), (512, "512x512"), (1024, "512x512@2x")] {
    if let data = render(size) {
        try? data.write(to: URL(fileURLWithPath: "\(outDir)/icon_\(name).png"))
    }
}
print("icon files written to \(outDir)")
