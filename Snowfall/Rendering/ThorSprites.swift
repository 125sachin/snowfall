import AppKit
import Metal

/// Procedurally drawn Thor (facing left) and Mjolnir, plus lightning, shockwave, crack and glow textures.
enum ThorSprites {
    struct Textures {
        let body: MTLTexture, hammer: MTLTexture, bolt: MTLTexture, ring: MTLTexture, crack: MTLTexture, glow: MTLTexture
    }

    static func makeTextures(device: MTLDevice) -> Textures? {
        func tex(_ d: MTLDevice, _ size: CGSize, _ draw: (CGContext, CGSize) -> Void) -> MTLTexture? {
            VehicleSprites.texture(device: d, size: size, draw: draw)
        }
        guard let body = tex(device, CGSize(width: 120, height: 150), drawBody),
              let hammer = tex(device, CGSize(width: 128, height: 40), drawHammer),
              let bolt = tex(device, CGSize(width: 64, height: 32), drawBolt),
              let ring = tex(device, CGSize(width: 128, height: 128), drawRing),
              let crack = tex(device, CGSize(width: 128, height: 128), drawCrack),
              let glow = tex(device, CGSize(width: 64, height: 64), drawGlow) else { return nil }
        return Textures(body: body, hammer: hammer, bolt: bolt, ring: ring, crack: crack, glow: glow)
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
    }

    private static func drawBody(_ c: CGContext, _ size: CGSize) {
        let red = rgb(190, 28, 36), darkRed = rgb(128, 16, 26), skin = rgb(238, 192, 152)
        let armor = rgb(58, 66, 80), silver = rgb(206, 212, 222), gold = rgb(244, 208, 88), brown = rgb(92, 62, 40)
        let black = rgb(28, 28, 32)
        c.setLineJoin(.round); c.setLineCap(.round)

        // Cape streaming behind (to the right).
        let cape = CGMutablePath()
        cape.move(to: CGPoint(x: 70, y: 118))
        cape.addCurve(to: CGPoint(x: 116, y: 38), control1: CGPoint(x: 104, y: 118), control2: CGPoint(x: 120, y: 78))
        cape.addLine(to: CGPoint(x: 100, y: 20)); cape.addLine(to: CGPoint(x: 92, y: 38)); cape.addLine(to: CGPoint(x: 80, y: 28))
        cape.addCurve(to: CGPoint(x: 70, y: 70), control1: CGPoint(x: 80, y: 50), control2: CGPoint(x: 76, y: 60))
        cape.closeSubpath()
        c.addPath(cape); c.setFillColor(red); c.fillPath()
        c.addPath(cape); c.setStrokeColor(darkRed); c.setLineWidth(1.5); c.strokePath()

        // Legs and boots.
        c.setStrokeColor(rgb(40, 44, 56)); c.setLineWidth(13)
        c.move(to: CGPoint(x: 48, y: 66)); c.addLine(to: CGPoint(x: 46, y: 16)); c.strokePath()
        c.move(to: CGPoint(x: 66, y: 66)); c.addLine(to: CGPoint(x: 68, y: 16)); c.strokePath()
        c.setFillColor(brown)
        c.addPath(CGPath(roundedRect: CGRect(x: 36, y: 0, width: 22, height: 20), cornerWidth: 5, cornerHeight: 5, transform: nil)); c.fillPath()
        c.addPath(CGPath(roundedRect: CGRect(x: 58, y: 0, width: 22, height: 20), cornerWidth: 5, cornerHeight: 5, transform: nil)); c.fillPath()
        c.setFillColor(silver); c.fill(CGRect(x: 38, y: 12, width: 18, height: 3)); c.fill(CGRect(x: 60, y: 12, width: 18, height: 3))

        // Torso armour with silver discs.
        let torso = CGMutablePath()
        torso.move(to: CGPoint(x: 38, y: 118)); torso.addLine(to: CGPoint(x: 80, y: 118))
        torso.addLine(to: CGPoint(x: 74, y: 62)); torso.addLine(to: CGPoint(x: 44, y: 62)); torso.closeSubpath()
        c.addPath(torso); c.setFillColor(armor); c.fillPath()
        c.addPath(torso); c.setStrokeColor(black); c.setLineWidth(1.5); c.strokePath()
        c.setFillColor(silver)
        for (x, y) in [(50.0, 104.0), (66.0, 104.0), (50.0, 88.0), (66.0, 88.0)] {
            c.fillEllipse(in: CGRect(x: x - 6, y: y - 6, width: 12, height: 12))
        }
        c.setFillColor(brown); c.fill(CGRect(x: 44, y: 64, width: 30, height: 7))
        c.setFillColor(gold); c.fill(CGRect(x: 55, y: 63, width: 8, height: 9))

        // Back arm.
        c.setStrokeColor(skin); c.setLineWidth(11)
        c.move(to: CGPoint(x: 78, y: 110)); c.addLine(to: CGPoint(x: 88, y: 82)); c.strokePath()
        c.setFillColor(skin); c.fillEllipse(in: CGRect(x: 82, y: 74, width: 12, height: 12))

        // Front arm forward (left) with silver bracer, gripping at (22, 100).
        c.setStrokeColor(skin); c.setLineWidth(12)
        c.move(to: CGPoint(x: 44, y: 110)); c.addLine(to: CGPoint(x: 26, y: 101)); c.strokePath()
        c.setStrokeColor(silver); c.setLineWidth(13)
        c.move(to: CGPoint(x: 34, y: 105)); c.addLine(to: CGPoint(x: 28, y: 102)); c.strokePath()
        c.setFillColor(skin); c.fillEllipse(in: CGRect(x: 15, y: 93, width: 14, height: 14))
        c.setFillColor(silver); c.fillEllipse(in: CGRect(x: 36, y: 106, width: 14, height: 14))      // shoulder

        // Head: face, blond hair streaming back, beard.
        c.setFillColor(skin); c.fillEllipse(in: CGRect(x: 43, y: 118, width: 28, height: 28))
        let hair = CGMutablePath()
        hair.move(to: CGPoint(x: 42, y: 134))
        hair.addCurve(to: CGPoint(x: 62, y: 150), control1: CGPoint(x: 42, y: 146), control2: CGPoint(x: 52, y: 151))
        hair.addCurve(to: CGPoint(x: 96, y: 118), control1: CGPoint(x: 80, y: 152), control2: CGPoint(x: 94, y: 136))
        hair.addCurve(to: CGPoint(x: 74, y: 128), control1: CGPoint(x: 90, y: 126), control2: CGPoint(x: 80, y: 130))
        hair.addLine(to: CGPoint(x: 66, y: 134)); hair.addLine(to: CGPoint(x: 52, y: 136)); hair.closeSubpath()
        c.addPath(hair); c.setFillColor(gold); c.fillPath()
        c.addPath(hair); c.setStrokeColor(rgb(190, 150, 50)); c.setLineWidth(1.2); c.strokePath()
        let beard = CGMutablePath()
        beard.move(to: CGPoint(x: 44, y: 128)); beard.addQuadCurve(to: CGPoint(x: 56, y: 114), control: CGPoint(x: 44, y: 114))
        beard.addQuadCurve(to: CGPoint(x: 70, y: 126), control: CGPoint(x: 68, y: 114)); beard.addLine(to: CGPoint(x: 62, y: 126))
        beard.addQuadCurve(to: CGPoint(x: 44, y: 128), control: CGPoint(x: 52, y: 122))
        c.addPath(beard); c.setFillColor(rgb(214, 176, 70)); c.fillPath()
        c.setFillColor(rgb(60, 130, 220)); c.fillEllipse(in: CGRect(x: 48, y: 132, width: 4.5, height: 4.5))     // eye
        c.setStrokeColor(rgb(150, 110, 40)); c.setLineWidth(1.6)
        c.move(to: CGPoint(x: 46, y: 139)); c.addLine(to: CGPoint(x: 54, y: 140)); c.strokePath()                  // brow
    }

    /// Mjolnir: steel head on a leather-wrapped handle. The grip (pivot) is at the right end.
    private static func drawHammer(_ c: CGContext, _ size: CGSize) {
        c.setLineJoin(.round); c.setLineCap(.round)
        c.setStrokeColor(rgb(66, 46, 34)); c.setLineWidth(9)
        c.move(to: CGPoint(x: 46, y: 20)); c.addLine(to: CGPoint(x: 120, y: 20)); c.strokePath()
        c.setStrokeColor(rgb(120, 86, 58)); c.setLineWidth(1.5)
        for i in 0..<9 { let x = 62 + CGFloat(i) * 6.5; c.move(to: CGPoint(x: x, y: 16)); c.addLine(to: CGPoint(x: x + 3, y: 24)) }
        c.strokePath()
        c.setFillColor(rgb(60, 60, 66)); c.fillEllipse(in: CGRect(x: 118, y: 14, width: 10, height: 12))   // wrist loop
        // Head.
        let head = CGPath(roundedRect: CGRect(x: 3, y: 3, width: 46, height: 34), cornerWidth: 5, cornerHeight: 5, transform: nil)
        c.addPath(head); c.setFillColor(rgb(150, 158, 170)); c.fillPath()
        c.setFillColor(rgb(196, 204, 214)); c.fill(CGRect(x: 6, y: 25, width: 40, height: 9))            // top bevel
        c.setFillColor(rgb(98, 104, 116)); c.fill(CGRect(x: 6, y: 6, width: 40, height: 8))              // bottom shade
        c.setStrokeColor(rgb(70, 76, 88)); c.setLineWidth(1)
        c.move(to: CGPoint(x: 12, y: 20)); c.addLine(to: CGPoint(x: 40, y: 20)); c.strokePath()
        c.addPath(head); c.setStrokeColor(rgb(40, 44, 52)); c.setLineWidth(1.8); c.strokePath()
        c.setFillColor(rgb(40, 44, 52)); c.fill(CGRect(x: 47, y: 12, width: 5, height: 16))             // collar
    }

    private static func drawBolt(_ c: CGContext, _ size: CGSize) {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let colors = [rgb(90, 140, 255, 0), rgb(110, 170, 255, 0.55), rgb(210, 235, 255, 0.95), rgb(255, 255, 255, 1),
                      rgb(210, 235, 255, 0.95), rgb(110, 170, 255, 0.55), rgb(90, 140, 255, 0)] as CFArray
        if let g = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 0.2, 0.4, 0.5, 0.6, 0.8, 1]) {
            c.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
    }

    private static func drawRing(_ c: CGContext, _ size: CGSize) {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctr = CGPoint(x: size.width / 2, y: size.height / 2)
        if let g = CGGradient(colorsSpace: cs, colors: [rgb(160, 210, 255, 0), rgb(160, 210, 255, 0), rgb(235, 248, 255, 0.95), rgb(160, 210, 255, 0)] as CFArray,
                              locations: [0, 0.72, 0.9, 1]) {
            c.drawRadialGradient(g, startCenter: ctr, startRadius: 0, endCenter: ctr, endRadius: size.width / 2, options: [])
        }
    }

    /// Jagged cracks radiating from the centre, with branches (a fixed pseudo-random pattern).
    private static func drawCrack(_ c: CGContext, _ size: CGSize) {
        c.setLineCap(.round); c.setLineJoin(.round)
        let ctr = CGPoint(x: size.width / 2, y: size.height / 2)
        var state: UInt64 = 0x9E3779B97F4A7C15
        func rnd() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((state >> 33) & 0xFFFF) / 65535
        }
        func crack(from: CGPoint, angle: CGFloat, length: CGFloat, depth: Int) {
            var p = from, a = angle, remaining = length
            let steps = max(3, Int(length / 9))
            for _ in 0..<steps {
                let seg = length / CGFloat(steps)
                a += (rnd() - 0.5) * 0.7
                let n = CGPoint(x: p.x + cos(a) * seg, y: p.y + sin(a) * seg)
                c.move(to: p); c.addLine(to: n)
                if depth < 2, rnd() < 0.3 { crack(from: n, angle: a + (rnd() < 0.5 ? 0.9 : -0.9), length: remaining * 0.5, depth: depth + 1) }
                p = n; remaining -= seg
            }
        }
        for pass in 0..<2 {
            state = 0x9E3779B97F4A7C15
            c.setStrokeColor(pass == 0 ? rgb(40, 70, 120, 0.9) : rgb(235, 248, 255, 0.95))
            c.setLineWidth(pass == 0 ? 3.2 : 1.4)
            for i in 0..<9 {
                let base = CGFloat(i) / 9 * .pi * 2 + (rnd() - 0.5) * 0.4
                crack(from: ctr, angle: base, length: size.width * (0.28 + 0.2 * rnd()), depth: 0)
            }
            c.strokePath()
        }
    }

    private static func drawGlow(_ c: CGContext, _ size: CGSize) {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctr = CGPoint(x: size.width / 2, y: size.height / 2)
        if let g = CGGradient(colorsSpace: cs, colors: [rgb(255, 255, 255, 1), rgb(170, 215, 255, 0.8), rgb(90, 150, 255, 0.25), rgb(90, 150, 255, 0)] as CFArray,
                              locations: [0, 0.25, 0.6, 1]) {
            c.drawRadialGradient(g, startCenter: ctr, startRadius: 0, endCenter: ctr, endRadius: size.width / 2, options: [])
        }
    }
}
