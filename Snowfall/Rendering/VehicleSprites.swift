import AppKit
import Metal

/// Procedurally drawn JCB-style backhoe loader, rendered once with Core Graphics into textures.
/// Design space: body 180 × 110 pt (origin bottom-left, facing LEFT, loader bucket at the left),
/// wheels are separate sprites so they can rotate. Textures are premultiplied BGRA.
enum VehicleSprites {
    static let bodySize = CGSize(width: 180, height: 110)
    /// (centre x, centre y, radius) in body design space.
    static let rearWheel = (x: CGFloat(128), y: CGFloat(30), r: CGFloat(30))
    static let frontWheel = (x: CGFloat(48), y: CGFloat(20), r: CGFloat(20))
    private static let pixelScale: CGFloat = 3

    static func makeTextures(device: MTLDevice) -> (body: MTLTexture, wheel: MTLTexture)? {
        guard let body = texture(device: device, size: bodySize, draw: drawBody),
              let wheel = texture(device: device, size: CGSize(width: 60, height: 60), draw: drawWheel) else { return nil }
        return (body, wheel)
    }

    private static func texture(device: MTLDevice, size: CGSize, draw: (CGContext, CGSize) -> Void) -> MTLTexture? {
        let w = Int(size.width * pixelScale), h = Int(size.height * pixelScale)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: cs, bitmapInfo: info) else { return nil }
        ctx.scaleBy(x: pixelScale, y: pixelScale)
        ctx.setAllowsAntialiasing(true); ctx.setShouldAntialias(true)
        draw(ctx, size)
        guard let data = ctx.data else { return nil }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        d.usage = .shaderRead
        guard let t = device.makeTexture(descriptor: d) else { return nil }
        t.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: data, bytesPerRow: w * 4)
        return t
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
    }

    private static func drawBody(_ c: CGContext, _ size: CGSize) {
        let yellow = rgb(247, 181, 0), darkYellow = rgb(214, 148, 0), black = rgb(34, 34, 38)
        let steel = rgb(70, 74, 82), glass = rgb(150, 205, 235, 0.92)
        c.setLineJoin(.round); c.setLineCap(.round)

        // Rear backhoe arm (behind the cab).
        c.setStrokeColor(steel); c.setLineWidth(7)
        c.move(to: CGPoint(x: 160, y: 62)); c.addLine(to: CGPoint(x: 176, y: 92)); c.addLine(to: CGPoint(x: 168, y: 40))
        c.strokePath()
        c.setStrokeColor(darkYellow); c.setLineWidth(4)
        c.move(to: CGPoint(x: 160, y: 62)); c.addLine(to: CGPoint(x: 176, y: 92)); c.strokePath()

        // Chassis.
        let chassis = CGPath(roundedRect: CGRect(x: 28, y: 26, width: 140, height: 38), cornerWidth: 8, cornerHeight: 8, transform: nil)
        c.addPath(chassis); c.setFillColor(yellow); c.fillPath()
        c.addPath(chassis); c.setStrokeColor(black); c.setLineWidth(1.5); c.strokePath()
        // Black belly / wheel arches shadow.
        c.setFillColor(black); c.fill(CGRect(x: 30, y: 24, width: 136, height: 6))

        // Engine hood.
        let hood = CGPath(roundedRect: CGRect(x: 28, y: 60, width: 56, height: 22), cornerWidth: 7, cornerHeight: 7, transform: nil)
        c.addPath(hood); c.setFillColor(yellow); c.fillPath()
        c.addPath(hood); c.setStrokeColor(black); c.setLineWidth(1.5); c.strokePath()
        c.setStrokeColor(darkYellow); c.setLineWidth(1.5)
        for i in 0..<4 { let x = 40 + CGFloat(i) * 9; c.move(to: CGPoint(x: x, y: 66)); c.addLine(to: CGPoint(x: x, y: 77)) }
        c.strokePath()
        // Exhaust pipe.
        c.setFillColor(black); c.fill(CGRect(x: 36, y: 82, width: 4, height: 14))

        // Cab: frame, glass, roof.
        let cab = CGMutablePath()
        cab.move(to: CGPoint(x: 88, y: 62)); cab.addLine(to: CGPoint(x: 94, y: 102))
        cab.addLine(to: CGPoint(x: 150, y: 102)); cab.addLine(to: CGPoint(x: 152, y: 62)); cab.closeSubpath()
        c.addPath(cab); c.setFillColor(black); c.fillPath()
        let win = CGMutablePath()
        win.move(to: CGPoint(x: 92, y: 66)); win.addLine(to: CGPoint(x: 97, y: 98))
        win.addLine(to: CGPoint(x: 146, y: 98)); win.addLine(to: CGPoint(x: 148, y: 66)); win.closeSubpath()
        c.addPath(win); c.setFillColor(glass); c.fillPath()
        // Driver silhouette.
        c.setFillColor(rgb(60, 70, 90, 0.85))
        c.fillEllipse(in: CGRect(x: 112, y: 82, width: 12, height: 12))
        c.fill(CGRect(x: 110, y: 66, width: 16, height: 18))
        // Roof.
        let roof = CGPath(roundedRect: CGRect(x: 88, y: 101, width: 70, height: 6), cornerWidth: 3, cornerHeight: 3, transform: nil)
        c.addPath(roof); c.setFillColor(yellow); c.fillPath()
        c.addPath(roof); c.setStrokeColor(black); c.setLineWidth(1.2); c.strokePath()
        // Beacon light.
        c.setFillColor(rgb(255, 140, 0)); c.fillEllipse(in: CGRect(x: 120, y: 106, width: 6, height: 4))

        // Front loader arm + bucket (blade face at x ≈ 2, ground at y = 0).
        c.setStrokeColor(steel); c.setLineWidth(6)
        c.move(to: CGPoint(x: 62, y: 52)); c.addLine(to: CGPoint(x: 26, y: 34)); c.strokePath()
        c.setStrokeColor(darkYellow); c.setLineWidth(3)
        c.move(to: CGPoint(x: 62, y: 56)); c.addLine(to: CGPoint(x: 28, y: 40)); c.strokePath()
        let bucket = CGMutablePath()
        bucket.move(to: CGPoint(x: 16, y: 1)); bucket.addLine(to: CGPoint(x: 2, y: 4))
        bucket.addCurve(to: CGPoint(x: 3, y: 46), control1: CGPoint(x: -1, y: 18), control2: CGPoint(x: 0, y: 34))
        bucket.addLine(to: CGPoint(x: 12, y: 52)); bucket.addLine(to: CGPoint(x: 26, y: 36))
        bucket.addLine(to: CGPoint(x: 24, y: 8)); bucket.closeSubpath()
        c.addPath(bucket); c.setFillColor(yellow); c.fillPath()
        c.addPath(bucket); c.setStrokeColor(black); c.setLineWidth(1.5); c.strokePath()
        // Cutting edge.
        c.setFillColor(steel); c.fill(CGRect(x: 2, y: 0, width: 16, height: 3))

        // Mudguards over the wheels.
        c.setFillColor(darkYellow)
        c.addArc(center: CGPoint(x: rearWheel.x, y: rearWheel.y), radius: rearWheel.r + 4, startAngle: 0.15, endAngle: .pi - 0.15, clockwise: false)
        c.setStrokeColor(darkYellow); c.setLineWidth(4); c.strokePath()
        c.addArc(center: CGPoint(x: frontWheel.x, y: frontWheel.y), radius: frontWheel.r + 3, startAngle: 0.2, endAngle: .pi - 0.2, clockwise: false)
        c.strokePath()
    }

    private static func drawWheel(_ c: CGContext, _ size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2), r = size.width / 2 - 0.5
        c.setFillColor(rgb(28, 28, 30)); c.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
        // Tread blocks.
        c.setStrokeColor(rgb(60, 60, 64)); c.setLineWidth(3)
        for i in 0..<18 {
            let a = CGFloat(i) / 18 * .pi * 2
            c.move(to: CGPoint(x: center.x + cos(a) * (r - 4), y: center.y + sin(a) * (r - 4)))
            c.addLine(to: CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r))
        }
        c.strokePath()
        let rim = r * 0.55
        c.setFillColor(rgb(236, 236, 240)); c.fillEllipse(in: CGRect(x: center.x - rim, y: center.y - rim, width: 2 * rim, height: 2 * rim))
        c.setStrokeColor(rgb(120, 120, 128)); c.setLineWidth(2)
        for i in 0..<5 {
            let a = CGFloat(i) / 5 * .pi * 2
            c.move(to: center); c.addLine(to: CGPoint(x: center.x + cos(a) * rim * 0.9, y: center.y + sin(a) * rim * 0.9))
        }
        c.strokePath()
        c.setFillColor(rgb(247, 181, 0)); c.fillEllipse(in: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8))
    }
}
