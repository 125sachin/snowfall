import AppKit
import Metal

/// Procedurally drawn red-and-blue web-slinger (facing left), plus web thread, web pattern and web ball.
enum SpiderSprites {
    struct Textures { let body: MTLTexture, thread: MTLTexture, web: MTLTexture, ball: MTLTexture }

    static func makeTextures(device: MTLDevice) -> Textures? {
        func tex(_ size: CGSize, _ draw: (CGContext, CGSize) -> Void) -> MTLTexture? {
            VehicleSprites.texture(device: device, size: size, draw: draw)
        }
        guard let body = tex(CGSize(width: 100, height: 140), drawBody),
              let thread = tex(CGSize(width: 64, height: 8), drawThread),
              let web = tex(CGSize(width: 128, height: 128), drawWeb),
              let ball = tex(CGSize(width: 32, height: 32), drawBall) else { return nil }
        return Textures(body: body, thread: thread, web: web, ball: ball)
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
    }

    private static func drawBody(_ c: CGContext, _ size: CGSize) {
        let red = rgb(206, 28, 36), darkRed = rgb(140, 14, 22), blue = rgb(38, 74, 170), darkBlue = rgb(22, 44, 110)
        let black = rgb(24, 24, 28), white = rgb(250, 250, 252)
        c.setLineJoin(.round); c.setLineCap(.round)

        // Legs trailing behind (blue suit, red boots).
        func leg(_ hip: CGPoint, _ knee: CGPoint, _ foot: CGPoint) {
            c.setStrokeColor(blue); c.setLineWidth(12)
            c.move(to: hip); c.addLine(to: knee); c.addLine(to: foot); c.strokePath()
            c.setStrokeColor(red); c.setLineWidth(11)
            let d = CGPoint(x: foot.x - knee.x, y: foot.y - knee.y)
            c.move(to: CGPoint(x: foot.x - d.x * 0.45, y: foot.y - d.y * 0.45)); c.addLine(to: foot); c.strokePath()
        }
        leg(CGPoint(x: 56, y: 56), CGPoint(x: 74, y: 36), CGPoint(x: 90, y: 20))
        leg(CGPoint(x: 50, y: 56), CGPoint(x: 62, y: 30), CGPoint(x: 70, y: 8))

        // Back arm trailing.
        c.setStrokeColor(red); c.setLineWidth(10)
        c.move(to: CGPoint(x: 68, y: 102)); c.addLine(to: CGPoint(x: 84, y: 94)); c.addLine(to: CGPoint(x: 92, y: 80)); c.strokePath()

        // Torso: red top with blue sides, belt, and a spider emblem.
        let torso = CGMutablePath()
        torso.move(to: CGPoint(x: 36, y: 108)); torso.addLine(to: CGPoint(x: 72, y: 108))
        torso.addLine(to: CGPoint(x: 64, y: 54)); torso.addLine(to: CGPoint(x: 44, y: 54)); torso.closeSubpath()
        c.addPath(torso); c.setFillColor(red); c.fillPath()
        c.saveGState(); c.addPath(torso); c.clip()
        c.setFillColor(blue); c.fill(CGRect(x: 30, y: 54, width: 14, height: 60)); c.fill(CGRect(x: 62, y: 54, width: 14, height: 60))
        c.setFillColor(darkBlue); c.fill(CGRect(x: 30, y: 54, width: 40, height: 12))
        c.restoreGState()
        c.addPath(torso); c.setStrokeColor(black); c.setLineWidth(1.4); c.strokePath()
        // Web lines on the torso.
        c.setStrokeColor(black.copy(alpha: 0.55)!); c.setLineWidth(0.9)
        for y in stride(from: CGFloat(66), through: 100, by: 11) {
            c.move(to: CGPoint(x: 44, y: y)); c.addQuadCurve(to: CGPoint(x: 64, y: y), control: CGPoint(x: 54, y: y - 5))
        }
        c.move(to: CGPoint(x: 54, y: 54)); c.addLine(to: CGPoint(x: 54, y: 108))
        c.strokePath()
        // Spider emblem.
        c.setFillColor(black); c.fillEllipse(in: CGRect(x: 49, y: 84, width: 9, height: 14))
        c.setStrokeColor(black); c.setLineWidth(1.6)
        for (dx, dy) in [(-9.0, 6.0), (-9.0, 0.0), (-8.0, -6.0), (9.0, 6.0), (9.0, 0.0), (8.0, -6.0)] as [(CGFloat, CGFloat)] {
            c.move(to: CGPoint(x: 53.5, y: 91)); c.addLine(to: CGPoint(x: 53.5 + dx, y: 91 + dy))
        }
        c.strokePath()

        // Front arm reaching up toward the web, hand at (22, 126).
        c.setStrokeColor(red); c.setLineWidth(11)
        c.move(to: CGPoint(x: 42, y: 104)); c.addLine(to: CGPoint(x: 30, y: 116)); c.addLine(to: CGPoint(x: 23, y: 125)); c.strokePath()
        c.setFillColor(red); c.fillEllipse(in: CGRect(x: 16, y: 119, width: 13, height: 13))

        // Head: red mask with web lines and large white lenses.
        let head = CGPath(ellipseIn: CGRect(x: 34, y: 108, width: 30, height: 32), transform: nil)
        c.addPath(head); c.setFillColor(red); c.fillPath()
        c.addPath(head); c.setStrokeColor(black); c.setLineWidth(1.4); c.strokePath()
        c.setStrokeColor(black.copy(alpha: 0.6)!); c.setLineWidth(0.9)
        for a in stride(from: CGFloat(0), to: .pi * 2, by: .pi / 4) {
            c.move(to: CGPoint(x: 49, y: 124)); c.addLine(to: CGPoint(x: 49 + cos(a) * 15, y: 124 + sin(a) * 16))
        }
        c.strokePath()
        for (cx, cy, rot) in [(41.0, 126.0, 0.5), (50.0, 119.0, 0.15)] as [(CGFloat, CGFloat, CGFloat)] {
            c.saveGState(); c.translateBy(x: cx, y: cy); c.rotate(by: rot)
            let lens = CGMutablePath()
            lens.move(to: CGPoint(x: -8, y: 3)); lens.addQuadCurve(to: CGPoint(x: 8, y: 6), control: CGPoint(x: 0, y: 9))
            lens.addQuadCurve(to: CGPoint(x: -6, y: -4), control: CGPoint(x: 3, y: -2)); lens.closeSubpath()
            c.addPath(lens); c.setFillColor(white); c.fillPath()
            c.addPath(lens); c.setStrokeColor(black); c.setLineWidth(1.4); c.strokePath()
            c.restoreGState()
        }
    }

    private static func drawThread(_ c: CGContext, _ size: CGSize) {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let colors = [rgb(255, 255, 255, 0), rgb(255, 255, 255, 0.55), rgb(255, 255, 255, 1), rgb(255, 255, 255, 0.55), rgb(255, 255, 255, 0)] as CFArray
        if let g = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 0.3, 0.5, 0.7, 1]) {
            c.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
    }

    /// A spider web: radial threads and sagging concentric rings.
    private static func drawWeb(_ c: CGContext, _ size: CGSize) {
        c.setLineCap(.round); c.setLineJoin(.round)
        let ctr = CGPoint(x: size.width / 2, y: size.height / 2), R = size.width / 2 - 3
        let spokes = 12
        func pt(_ i: Int, _ r: CGFloat) -> CGPoint {
            let a = CGFloat(i) / CGFloat(spokes) * .pi * 2
            return CGPoint(x: ctr.x + cos(a) * r, y: ctr.y + sin(a) * r)
        }
        for pass in 0..<2 {
            c.setStrokeColor(pass == 0 ? rgb(190, 215, 255, 0.55) : rgb(255, 255, 255, 0.95))
            c.setLineWidth(pass == 0 ? 3.4 : 1.3)
            for i in 0..<spokes { c.move(to: ctr); c.addLine(to: pt(i, R)) }
            for ring in 1...5 {
                let r = R * CGFloat(ring) / 5
                for i in 0..<spokes {
                    let a = pt(i, r), b = pt((i + 1) % spokes, r)
                    let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                    let sag = CGPoint(x: mid.x + (ctr.x - mid.x) * 0.12, y: mid.y + (ctr.y - mid.y) * 0.12)
                    if i == 0 { c.move(to: a) }
                    c.addQuadCurve(to: b, control: sag)
                }
            }
            c.strokePath()
        }
    }

    private static func drawBall(_ c: CGContext, _ size: CGSize) {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctr = CGPoint(x: size.width / 2, y: size.height / 2)
        if let g = CGGradient(colorsSpace: cs, colors: [rgb(255, 255, 255, 1), rgb(235, 245, 255, 0.95), rgb(200, 225, 255, 0)] as CFArray, locations: [0, 0.55, 1]) {
            c.drawRadialGradient(g, startCenter: ctr, startRadius: 0, endCenter: ctr, endRadius: size.width / 2, options: [])
        }
    }
}
