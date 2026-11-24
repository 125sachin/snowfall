import AppKit
import Metal

/// Procedurally drawn armoured hero (facing left), plus beam and glow textures.
enum IronManSprites {
    struct Textures { let body: MTLTexture; let beam: MTLTexture; let glow: MTLTexture }

    static func makeTextures(device: MTLDevice) -> Textures? {
        guard let body = VehicleSprites.texture(device: device, size: CGSize(width: 110, height: 150), draw: drawBody),
              let beam = VehicleSprites.texture(device: device, size: CGSize(width: 64, height: 32), draw: drawBeam),
              let glow = VehicleSprites.texture(device: device, size: CGSize(width: 64, height: 64), draw: drawGlow) else { return nil }
        return Textures(body: body, beam: beam, glow: glow)
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
    }

    private static func drawBody(_ c: CGContext, _ size: CGSize) {
        let red = rgb(176, 22, 30), darkRed = rgb(118, 12, 20), gold = rgb(240, 186, 52), darkGold = rgb(186, 132, 24)
        let black = rgb(28, 28, 32)
        c.setLineJoin(.round); c.setLineCap(.round)

        // Boot jets trailing below (flames).
        func flame(_ x: CGFloat) {
            let outer = CGMutablePath()
            outer.move(to: CGPoint(x: x - 8, y: 30)); outer.addQuadCurve(to: CGPoint(x: x + 2, y: 2), control: CGPoint(x: x - 6, y: 12))
            outer.addQuadCurve(to: CGPoint(x: x + 8, y: 30), control: CGPoint(x: x + 8, y: 12)); outer.closeSubpath()
            c.addPath(outer); c.setFillColor(rgb(255, 120, 30, 0.95)); c.fillPath()
            let inner = CGMutablePath()
            inner.move(to: CGPoint(x: x - 4, y: 30)); inner.addQuadCurve(to: CGPoint(x: x + 1, y: 12), control: CGPoint(x: x - 3, y: 20))
            inner.addQuadCurve(to: CGPoint(x: x + 4, y: 30), control: CGPoint(x: x + 4, y: 20)); inner.closeSubpath()
            c.addPath(inner); c.setFillColor(rgb(255, 236, 140)); c.fillPath()
        }
        flame(46); flame(66)

        // Back arm trailing.
        c.setStrokeColor(darkRed); c.setLineWidth(11)
        c.move(to: CGPoint(x: 78, y: 108)); c.addLine(to: CGPoint(x: 94, y: 90)); c.strokePath()
        c.setFillColor(darkGold); c.fillEllipse(in: CGRect(x: 89, y: 83, width: 12, height: 12))

        // Legs.
        c.setStrokeColor(red); c.setLineWidth(13)
        c.move(to: CGPoint(x: 46, y: 72)); c.addLine(to: CGPoint(x: 46, y: 48)); c.strokePath()
        c.move(to: CGPoint(x: 66, y: 72)); c.addLine(to: CGPoint(x: 66, y: 48)); c.strokePath()
        c.setStrokeColor(gold); c.setLineWidth(12)
        c.move(to: CGPoint(x: 46, y: 48)); c.addLine(to: CGPoint(x: 46, y: 32)); c.strokePath()
        c.move(to: CGPoint(x: 66, y: 48)); c.addLine(to: CGPoint(x: 66, y: 32)); c.strokePath()
        c.setFillColor(darkGold)
        c.fillEllipse(in: CGRect(x: 40, y: 44, width: 12, height: 10)); c.fillEllipse(in: CGRect(x: 60, y: 44, width: 12, height: 10))

        // Torso.
        let torso = CGMutablePath()
        torso.move(to: CGPoint(x: 34, y: 116)); torso.addLine(to: CGPoint(x: 82, y: 116))
        torso.addLine(to: CGPoint(x: 74, y: 74)); torso.addLine(to: CGPoint(x: 42, y: 74)); torso.closeSubpath()
        c.addPath(torso); c.setFillColor(red); c.fillPath()
        c.addPath(torso); c.setStrokeColor(darkRed); c.setLineWidth(1.5); c.strokePath()
        c.setFillColor(gold); c.fill(CGRect(x: 43, y: 74, width: 30, height: 9))           // abdomen plate
        c.setFillColor(darkGold); c.fill(CGRect(x: 43, y: 80, width: 30, height: 2))
        c.setFillColor(gold)
        c.addPath(CGPath(roundedRect: CGRect(x: 36, y: 100, width: 34, height: 14), cornerWidth: 6, cornerHeight: 6, transform: nil)); c.fillPath()   // chest plate
        // Arc reactor.
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        c.setFillColor(rgb(60, 70, 80)); c.fillEllipse(in: CGRect(x: 40, y: 98, width: 17, height: 17))
        if let g = CGGradient(colorsSpace: cs, colors: [rgb(255, 255, 255), rgb(120, 220, 255), rgb(30, 140, 255, 0.0)] as CFArray, locations: [0, 0.4, 1]) {
            c.drawRadialGradient(g, startCenter: CGPoint(x: 48.5, y: 106.5), startRadius: 0, endCenter: CGPoint(x: 48.5, y: 106.5), endRadius: 11, options: [])
        }

        // Shoulders.
        c.setFillColor(gold); c.fillEllipse(in: CGRect(x: 28, y: 104, width: 16, height: 16)); c.fillEllipse(in: CGRect(x: 72, y: 104, width: 16, height: 16))

        // Front arm reaching forward (left) with a glowing repulsor palm.
        c.setStrokeColor(red); c.setLineWidth(11)
        c.move(to: CGPoint(x: 36, y: 112)); c.addLine(to: CGPoint(x: 18, y: 102)); c.strokePath()
        c.setStrokeColor(gold); c.setLineWidth(10)
        c.move(to: CGPoint(x: 18, y: 102)); c.addLine(to: CGPoint(x: 8, y: 98)); c.strokePath()
        c.setFillColor(darkGold); c.fillEllipse(in: CGRect(x: 1, y: 92, width: 13, height: 13))
        if let g = CGGradient(colorsSpace: cs, colors: [rgb(255, 255, 255), rgb(120, 220, 255, 0.8), rgb(30, 140, 255, 0)] as CFArray, locations: [0, 0.5, 1]) {
            c.drawRadialGradient(g, startCenter: CGPoint(x: 2, y: 98), startRadius: 0, endCenter: CGPoint(x: 2, y: 98), endRadius: 6, options: [])
        }

        // Helmet: red dome, gold faceplate facing left, glowing eye slits.
        let helmet = CGPath(ellipseIn: CGRect(x: 36, y: 116, width: 30, height: 32), transform: nil)
        c.addPath(helmet); c.setFillColor(red); c.fillPath()
        let face = CGMutablePath()
        face.move(to: CGPoint(x: 38, y: 138)); face.addQuadCurve(to: CGPoint(x: 42, y: 118), control: CGPoint(x: 35, y: 128))
        face.addLine(to: CGPoint(x: 56, y: 117)); face.addQuadCurve(to: CGPoint(x: 60, y: 138), control: CGPoint(x: 62, y: 126))
        face.closeSubpath()
        c.addPath(face); c.setFillColor(gold); c.fillPath()
        c.addPath(helmet); c.setStrokeColor(darkRed); c.setLineWidth(1.5); c.strokePath()
        // Eyes: bright white slits with a cool glow.
        if let g = CGGradient(colorsSpace: cs, colors: [rgb(255, 255, 255), rgb(190, 235, 255, 0.7), rgb(120, 200, 255, 0)] as CFArray, locations: [0, 0.45, 1]) {
            c.drawRadialGradient(g, startCenter: CGPoint(x: 41, y: 133), startRadius: 0, endCenter: CGPoint(x: 41, y: 133), endRadius: 6, options: [])
        }
        c.setFillColor(rgb(255, 255, 255))
        c.addPath(CGPath(roundedRect: CGRect(x: 38.5, y: 131.5, width: 8, height: 3.4), cornerWidth: 1.7, cornerHeight: 1.7, transform: nil)); c.fillPath()
        c.setStrokeColor(black); c.setLineWidth(1)
        c.move(to: CGPoint(x: 40, y: 124)); c.addLine(to: CGPoint(x: 48, y: 123)); c.strokePath()     // mouth slit
    }

    /// Horizontal beam: a bright core with an orange-red glow fading to nothing vertically.
    private static func drawBeam(_ c: CGContext, _ size: CGSize) {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let colors = [rgb(255, 60, 30, 0), rgb(255, 80, 30, 0.55), rgb(255, 200, 120, 0.95), rgb(255, 255, 255, 1),
                      rgb(255, 200, 120, 0.95), rgb(255, 80, 30, 0.55), rgb(255, 60, 30, 0)] as CFArray
        if let g = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 0.2, 0.4, 0.5, 0.6, 0.8, 1]) {
            c.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size.height), options: [])
        }
    }

    private static func drawGlow(_ c: CGContext, _ size: CGSize) {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctr = CGPoint(x: size.width / 2, y: size.height / 2)
        if let g = CGGradient(colorsSpace: cs, colors: [rgb(255, 255, 255, 1), rgb(255, 190, 90, 0.8), rgb(255, 80, 30, 0.25), rgb(255, 60, 30, 0)] as CFArray,
                              locations: [0, 0.25, 0.6, 1]) {
            c.drawRadialGradient(g, startCenter: ctr, startRadius: 0, endCenter: ctr, endRadius: size.width / 2, options: [])
        }
    }
}
