import AppKit
import Metal

/// Procedurally drawn art for the lighter helpers (penguin, kid, snowball, splat, snowman, sleigh).
/// Everything faces LEFT. Core Graphics → premultiplied BGRA textures, built on first use.
enum PropSprites {
    typealias Textures = [PropKind: MTLTexture]

    static func makeTextures(device: MTLDevice) -> Textures? {
        var out: Textures = [:]
        let specs: [(PropKind, CGSize, (CGContext, CGSize) -> Void)] = [
            (.penguin, CGSize(width: 92, height: 46), drawPenguin),
            (.kid, CGSize(width: 56, height: 92), drawKid),
            (.kidArm, CGSize(width: 40, height: 14), drawArm),
            (.snowball, CGSize(width: 32, height: 32), drawSnowball),
            (.splat, CGSize(width: 96, height: 96), drawSplat),
            (.hat, CGSize(width: 52, height: 38), drawHat),
            (.scarf, CGSize(width: 64, height: 44), drawScarf),
            (.carrot, CGSize(width: 30, height: 9), drawCarrot),
            (.coal, CGSize(width: 8, height: 8), drawCoal),
            (.stick, CGSize(width: 51, height: 8), drawStick),
            (.sleigh, CGSize(width: 560, height: 150), drawSleigh),
        ]
        for (kind, size, draw) in specs {
            guard let t = VehicleSprites.texture(device: device, size: size, draw: draw) else { return nil }
            out[kind] = t
        }
        return out
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
    }

    private static func ellipse(_ c: CGContext, _ r: CGRect, fill: CGColor, stroke: CGColor? = nil, width: CGFloat = 1) {
        c.setFillColor(fill); c.fillEllipse(in: r)
        if let s = stroke { c.setStrokeColor(s); c.setLineWidth(width); c.strokeEllipse(in: r) }
    }

    private static func ball(_ c: CGContext, center: CGPoint, r: CGFloat) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let g = CGGradient(colorsSpace: space, colors: [rgb(255, 255, 255), rgb(226, 236, 248), rgb(184, 204, 230)] as CFArray,
                           locations: [0, 0.65, 1])!
        c.saveGState()
        c.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)); c.clip()
        c.drawRadialGradient(g, startCenter: CGPoint(x: center.x - r * 0.3, y: center.y + r * 0.35), startRadius: 0,
                             endCenter: center, endRadius: r, options: [.drawsAfterEndLocation])
        c.restoreGState()
        c.setStrokeColor(rgb(150, 176, 210, 0.7)); c.setLineWidth(max(0.8, r * 0.03))
        c.strokeEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
    }

    // MARK: Penguin (belly-down slide, heading left)

    private static func drawPenguin(_ c: CGContext, _ size: CGSize) {
        let black = rgb(28, 32, 46), white = rgb(246, 248, 252), orange = rgb(247, 150, 30)
        c.setLineCap(.round); c.setLineJoin(.round)
        // Feet trailing behind.
        c.setFillColor(orange)
        c.fillEllipse(in: CGRect(x: 78, y: 6, width: 12, height: 6)); c.fillEllipse(in: CGRect(x: 74, y: 12, width: 11, height: 6))
        // Body: dark back, white belly along the ground.
        ellipse(c, CGRect(x: 20, y: 6, width: 68, height: 32), fill: black)
        ellipse(c, CGRect(x: 24, y: 5, width: 60, height: 17), fill: white)
        // Flipper swept back.
        c.saveGState(); c.translateBy(x: 54, y: 22); c.rotate(by: -0.35)
        ellipse(c, CGRect(x: -2, y: -4, width: 30, height: 8), fill: rgb(40, 46, 64)); c.restoreGState()
        // Head, face patch, eye, beak (pointing left).
        ellipse(c, CGRect(x: 8, y: 18, width: 28, height: 24), fill: black)
        ellipse(c, CGRect(x: 10, y: 20, width: 20, height: 15), fill: white)
        ellipse(c, CGRect(x: 15, y: 29, width: 5.5, height: 6), fill: black)
        ellipse(c, CGRect(x: 16.5, y: 31.5, width: 2, height: 2), fill: white)
        let beak = CGMutablePath()
        beak.move(to: CGPoint(x: 10, y: 28)); beak.addLine(to: CGPoint(x: 1, y: 25)); beak.addLine(to: CGPoint(x: 10, y: 23)); beak.closeSubpath()
        c.addPath(beak); c.setFillColor(orange); c.fillPath()
    }

    // MARK: Kid (standing, facing left; arm is a separate sprite)

    private static func drawKid(_ c: CGContext, _ size: CGSize) {
        let coat = rgb(214, 54, 56), pants = rgb(40, 58, 120), boots = rgb(56, 40, 36), skin = rgb(245, 205, 170)
        let hat = rgb(46, 110, 190), scarf = rgb(250, 200, 40)
        c.setLineCap(.round); c.setLineJoin(.round)
        // Legs.
        c.setStrokeColor(pants); c.setLineWidth(9)
        c.move(to: CGPoint(x: 23, y: 36)); c.addLine(to: CGPoint(x: 21, y: 9)); c.move(to: CGPoint(x: 34, y: 36)); c.addLine(to: CGPoint(x: 36, y: 9)); c.strokePath()
        c.setFillColor(boots)
        c.fill(CGRect(x: 12, y: 1, width: 14, height: 9)); c.fill(CGRect(x: 30, y: 1, width: 14, height: 9))
        // Coat.
        let body = CGPath(roundedRect: CGRect(x: 14, y: 32, width: 30, height: 34), cornerWidth: 9, cornerHeight: 9, transform: nil)
        c.addPath(body); c.setFillColor(coat); c.fillPath()
        c.setStrokeColor(rgb(150, 30, 34)); c.setLineWidth(1); c.addPath(body); c.strokePath()
        c.setFillColor(rgb(250, 235, 120)); for y in [40.0, 49.0, 58.0] { c.fillEllipse(in: CGRect(x: 25, y: y, width: 3.5, height: 3.5)) }
        // Scarf.
        c.setFillColor(scarf); c.fill(CGRect(x: 15, y: 62, width: 28, height: 8))
        c.setFillColor(rgb(214, 54, 56)); for x in stride(from: 19.0, to: 42.0, by: 8.0) { c.fill(CGRect(x: x, y: 62, width: 3, height: 8)) }
        // Head, face (looking left), beanie.
        ellipse(c, CGRect(x: 14, y: 66, width: 28, height: 24), fill: skin, stroke: rgb(190, 150, 120), width: 0.8)
        ellipse(c, CGRect(x: 19, y: 77, width: 3.4, height: 3.8), fill: rgb(40, 40, 50))
        ellipse(c, CGRect(x: 15, y: 72, width: 4, height: 3), fill: rgb(240, 150, 140))
        let beanie = CGMutablePath()
        beanie.addArc(center: CGPoint(x: 28, y: 82), radius: 15, startAngle: 0.1, endAngle: .pi - 0.1, clockwise: false)
        beanie.closeSubpath()
        c.addPath(beanie); c.setFillColor(hat); c.fillPath()
        c.setFillColor(rgb(235, 240, 250)); c.fill(CGRect(x: 13.5, y: 80, width: 29, height: 4))
        ellipse(c, CGRect(x: 23, y: 94 - 6, width: 9, height: 9), fill: rgb(240, 245, 252))
    }

    /// Sleeve with a mitten at the +x end; the shoulder joint is at the left end.
    private static func drawArm(_ c: CGContext, _ size: CGSize) {
        c.setLineCap(.round)
        c.setStrokeColor(rgb(214, 54, 56)); c.setLineWidth(9)
        c.move(to: CGPoint(x: 5, y: 7)); c.addLine(to: CGPoint(x: 28, y: 7)); c.strokePath()
        ellipse(c, CGRect(x: 27, y: 1.5, width: 11, height: 11), fill: rgb(46, 110, 190))
    }

    // MARK: Snowball, splat

    private static func drawSnowball(_ c: CGContext, _ size: CGSize) {
        ball(c, center: CGPoint(x: 16, y: 16), r: 14.5)
        c.setFillColor(rgb(176, 198, 226, 0.8))
        for (x, y, r) in [(10.0, 20.0, 1.6), (20.0, 11.0, 1.9), (21.0, 21.0, 1.3), (11.0, 10.0, 1.2)] {
            c.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
        }
    }

    private static func drawSplat(_ c: CGContext, _ size: CGSize) {
        let center = CGPoint(x: 48, y: 48)
        let path = CGMutablePath()
        let lobes = 11
        for i in 0..<lobes {
            let a = CGFloat(i) / CGFloat(lobes) * 2 * .pi
            let r: CGFloat = 20 + CGFloat((i * 7) % 5) * 5.5
            let p = CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r)
            path.addEllipse(in: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14))
            // Streaks flung outward.
            let q = CGPoint(x: center.x + cos(a) * (r + 12), y: center.y + sin(a) * (r + 12))
            path.addEllipse(in: CGRect(x: q.x - 3, y: q.y - 3, width: 6, height: 6))
        }
        path.addEllipse(in: CGRect(x: 48 - 22, y: 48 - 20, width: 44, height: 40))
        c.addPath(path); c.setFillColor(rgb(150, 178, 214, 0.55)); c.fillPath()
        c.saveGState(); c.translateBy(x: -1.5, y: 1.5)
        c.addPath(path); c.setFillColor(rgb(255, 255, 255, 0.97)); c.fillPath(); c.restoreGState()
    }

    // MARK: Snowman parts

    private static func drawHat(_ c: CGContext, _ size: CGSize) {
        c.setFillColor(rgb(30, 30, 38))
        c.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: 52, height: 6), cornerWidth: 3, cornerHeight: 3, transform: nil)); c.fillPath()
        c.addPath(CGPath(roundedRect: CGRect(x: 9, y: 4, width: 34, height: 34), cornerWidth: 3, cornerHeight: 3, transform: nil)); c.fillPath()
        c.setFillColor(rgb(210, 46, 56)); c.fill(CGRect(x: 9, y: 7, width: 34, height: 7))
        c.setFillColor(rgb(255, 255, 255, 0.18)); c.fill(CGRect(x: 13, y: 16, width: 5, height: 20))      // highlight
    }

    /// A band for the neck (top) with a tail hanging down on the right.
    private static func drawScarf(_ c: CGContext, _ size: CGSize) {
        let red = rgb(210, 46, 56), light = rgb(250, 232, 232)
        c.setFillColor(red)
        c.addPath(CGPath(roundedRect: CGRect(x: 0, y: 32, width: 64, height: 12), cornerWidth: 6, cornerHeight: 6, transform: nil)); c.fillPath()
        c.fill(CGRect(x: 42, y: 4, width: 13, height: 34))
        c.setFillColor(light)
        c.fill(CGRect(x: 42, y: 12, width: 13, height: 3.5)); c.fill(CGRect(x: 42, y: 21, width: 13, height: 3.5))
        for x in stride(from: 6.0, to: 56.0, by: 14.0) { c.fill(CGRect(x: x, y: 33, width: 3.5, height: 10)) }
        c.setStrokeColor(rgb(150, 24, 34)); c.setLineWidth(0.8)
        c.stroke(CGRect(x: 42, y: 4, width: 13, height: 34))
    }

    /// Carrot nose: wide at the right (the face), tip at the left.
    private static func drawCarrot(_ c: CGContext, _ size: CGSize) {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 30, y: 8)); p.addLine(to: CGPoint(x: 1, y: 4.5)); p.addLine(to: CGPoint(x: 30, y: 1)); p.closeSubpath()
        c.addPath(p); c.setFillColor(rgb(244, 124, 30)); c.fillPath()
        c.setStrokeColor(rgb(200, 90, 20)); c.setLineWidth(0.8)
        for x in [10.0, 17.0, 24.0] { c.move(to: CGPoint(x: x, y: 2.8)); c.addLine(to: CGPoint(x: x, y: 6.2)) }
        c.strokePath()
    }

    private static func drawCoal(_ c: CGContext, _ size: CGSize) {
        ellipse(c, CGRect(x: 0.5, y: 0.5, width: 7, height: 7), fill: rgb(34, 34, 42))
        ellipse(c, CGRect(x: 2, y: 4, width: 2, height: 2), fill: rgb(255, 255, 255, 0.35))
    }

    /// Twig: the root is at the left end, with a fork near the tip.
    private static func drawStick(_ c: CGContext, _ size: CGSize) {
        c.setLineCap(.round); c.setStrokeColor(rgb(110, 76, 44)); c.setLineWidth(3.2)
        c.move(to: CGPoint(x: 2, y: 4)); c.addLine(to: CGPoint(x: 48, y: 4))
        c.move(to: CGPoint(x: 32, y: 4)); c.addLine(to: CGPoint(x: 44, y: 7.2))
        c.move(to: CGPoint(x: 38, y: 4)); c.addLine(to: CGPoint(x: 47, y: 0.8))
        c.strokePath()
    }

    // MARK: Sleigh (560 × 150): reindeer on the left, Santa in the sleigh on the right

    private static func reindeer(_ c: CGContext, x: CGFloat, lead: Bool, phase: CGFloat) {
        let brown = rgb(140, 92, 56), dark = rgb(96, 62, 36), antler = rgb(205, 180, 140)
        c.setLineCap(.round); c.setLineJoin(.round)
        // Legs in a gallop.
        c.setStrokeColor(dark); c.setLineWidth(5)
        for (dx, a) in [(6.0, 0.7), (16.0, -0.5), (58.0, 0.5), (68.0, -0.7)] {
            let hip = CGPoint(x: x + CGFloat(dx), y: 62)
            let foot = CGPoint(x: hip.x + sin(CGFloat(a) + phase) * 18, y: 24 + cos(CGFloat(a) + phase) * 4)
            c.move(to: hip); c.addLine(to: CGPoint(x: (hip.x + foot.x) / 2, y: 44)); c.addLine(to: foot)
        }
        c.strokePath()
        // Body, neck, head (facing left).
        ellipse(c, CGRect(x: x + 2, y: 52, width: 78, height: 34), fill: brown)
        c.setStrokeColor(brown); c.setLineWidth(15)
        c.move(to: CGPoint(x: x + 6, y: 78)); c.addLine(to: CGPoint(x: x - 12, y: 100)); c.strokePath()
        ellipse(c, CGRect(x: x - 34, y: 92, width: 28, height: 18), fill: brown)
        ellipse(c, CGRect(x: x - 36, y: 94, width: 10, height: 10), fill: lead ? rgb(236, 40, 40) : rgb(60, 40, 30))
        ellipse(c, CGRect(x: x - 20, y: 101, width: 3.4, height: 3.4), fill: rgb(20, 20, 24))
        // Antlers.
        c.setStrokeColor(antler); c.setLineWidth(3)
        c.move(to: CGPoint(x: x - 12, y: 108)); c.addLine(to: CGPoint(x: x - 4, y: 128)); c.addLine(to: CGPoint(x: x + 6, y: 140))
        c.move(to: CGPoint(x: x - 4, y: 128)); c.addLine(to: CGPoint(x: x - 14, y: 138))
        c.move(to: CGPoint(x: x - 4, y: 118)); c.addLine(to: CGPoint(x: x + 6, y: 124))
        c.strokePath()
        // Tail.
        ellipse(c, CGRect(x: x + 78, y: 74, width: 9, height: 8), fill: rgb(240, 236, 230))
    }

    private static func drawSleigh(_ c: CGContext, _ size: CGSize) {
        c.setLineCap(.round); c.setLineJoin(.round)
        // Harness line running the length of the team to the sleigh.
        c.setStrokeColor(rgb(120, 86, 40)); c.setLineWidth(2.2)
        c.move(to: CGPoint(x: 40, y: 84)); c.addLine(to: CGPoint(x: 330, y: 70)); c.strokePath()
        reindeer(c, x: 48, lead: true, phase: 0)
        reindeer(c, x: 150, lead: false, phase: 0.9)
        reindeer(c, x: 252, lead: false, phase: 0.4)
        // Sleigh: red curved body with a gold runner.
        let body = CGMutablePath()
        body.move(to: CGPoint(x: 345, y: 96)); body.addQuadCurve(to: CGPoint(x: 370, y: 40), control: CGPoint(x: 340, y: 50))
        body.addLine(to: CGPoint(x: 520, y: 40)); body.addQuadCurve(to: CGPoint(x: 540, y: 112), control: CGPoint(x: 548, y: 66))
        body.addLine(to: CGPoint(x: 480, y: 112)); body.addLine(to: CGPoint(x: 400, y: 92)); body.closeSubpath()
        c.addPath(body); c.setFillColor(rgb(200, 36, 44)); c.fillPath()
        c.addPath(body); c.setStrokeColor(rgb(130, 18, 28)); c.setLineWidth(2); c.strokePath()
        c.setStrokeColor(rgb(244, 190, 60)); c.setLineWidth(5)
        c.move(to: CGPoint(x: 346, y: 100)); c.addQuadCurve(to: CGPoint(x: 372, y: 22), control: CGPoint(x: 328, y: 34))
        c.addLine(to: CGPoint(x: 528, y: 22)); c.addQuadCurve(to: CGPoint(x: 552, y: 70), control: CGPoint(x: 556, y: 34)); c.strokePath()
        c.setStrokeColor(rgb(244, 190, 60)); c.setLineWidth(3); c.move(to: CGPoint(x: 400, y: 24)); c.addLine(to: CGPoint(x: 400, y: 42)); c.move(to: CGPoint(x: 470, y: 24)); c.addLine(to: CGPoint(x: 470, y: 42)); c.strokePath()
        // Gift sack behind Santa.
        ellipse(c, CGRect(x: 492, y: 70, width: 44, height: 48), fill: rgb(150, 100, 60), stroke: rgb(100, 66, 40), width: 1.5)
        ellipse(c, CGRect(x: 500, y: 112, width: 14, height: 10), fill: rgb(70, 160, 90))
        // Santa: coat, belt, face, beard, hat.
        ellipse(c, CGRect(x: 428, y: 78, width: 54, height: 46), fill: rgb(214, 40, 48))
        c.setFillColor(rgb(30, 30, 36)); c.fill(CGRect(x: 432, y: 94, width: 46, height: 6))
        c.setFillColor(rgb(244, 190, 60)); c.fill(CGRect(x: 448, y: 93, width: 8, height: 8))
        ellipse(c, CGRect(x: 424, y: 112, width: 34, height: 30), fill: rgb(245, 205, 170))
        ellipse(c, CGRect(x: 418, y: 98, width: 28, height: 24), fill: rgb(250, 250, 252))
        ellipse(c, CGRect(x: 425, y: 126, width: 3.4, height: 3.8), fill: rgb(30, 30, 36))
        let cap = CGMutablePath()
        cap.move(to: CGPoint(x: 422, y: 134)); cap.addQuadCurve(to: CGPoint(x: 464, y: 164), control: CGPoint(x: 424, y: 168))
        cap.addLine(to: CGPoint(x: 460, y: 134)); cap.closeSubpath()
        c.addPath(cap); c.setFillColor(rgb(214, 40, 48)); c.fillPath()
        c.setFillColor(rgb(250, 250, 252)); c.fill(CGRect(x: 420, y: 130, width: 42, height: 8))
        ellipse(c, CGRect(x: 458, y: 156, width: 11, height: 11), fill: rgb(250, 250, 252))
        // Reins to the first reindeer's harness.
        c.setStrokeColor(rgb(120, 86, 40)); c.setLineWidth(1.6)
        c.move(to: CGPoint(x: 428, y: 100)); c.addLine(to: CGPoint(x: 330, y: 72)); c.strokePath()
    }
}
