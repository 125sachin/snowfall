// Renders the app icon (the same "snowflake" SF Symbol shown in the menu bar, white on a blue
// gradient squircle) into Snowfall/Resources/Assets.xcassets/AppIcon.appiconset.
import AppKit

let out = CommandLine.arguments[1]
let sizes: [(pt: Int, scale: Int)] = [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)]

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.098                                   // macOS icon grid margin
    let body = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowBlurRadius = s * 0.02; shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35); shadow.set()
    NSColor(red: 0.10, green: 0.18, blue: 0.40, alpha: 1).setFill(); path.fill()
    NSGraphicsContext.current?.restoreGraphicsState()
    path.addClip()
    NSGradient(colors: [NSColor(red: 0.36, green: 0.62, blue: 0.98, alpha: 1), NSColor(red: 0.08, green: 0.16, blue: 0.42, alpha: 1)])!
        .draw(in: body, angle: -90)
    let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.56, weight: .semibold)
    if let sym = NSImage(systemSymbolName: "snowflake", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
        let tinted = NSImage(size: sym.size, flipped: false) { r in
            sym.draw(in: r); NSColor.white.set(); r.fill(using: .sourceIn); return true
        }
        let w = tinted.size.width, h = tinted.size.height
        tinted.draw(in: NSRect(x: (s - w) / 2, y: (s - h) / 2, width: w, height: h))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for (pt, sc) in sizes {
    let name = "icon_\(pt)x\(pt)@\(sc)x.png"
    try! render(pt * sc).write(to: URL(fileURLWithPath: out + "/" + name))
    images.append(["idiom": "mac", "size": "\(pt)x\(pt)", "scale": "\(sc)x", "filename": name])
}
let json = try! JSONSerialization.data(withJSONObject: ["images": images, "info": ["version": 1, "author": "xcode"]], options: [.prettyPrinted])
try! json.write(to: URL(fileURLWithPath: out + "/Contents.json"))
