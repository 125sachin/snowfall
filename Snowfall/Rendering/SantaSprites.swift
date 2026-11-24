import AppKit
import Metal

/// Procedurally drawn Santa (facing left) and his magic wand, rendered once with Core Graphics.
/// Design space is documented by `SantaMetrics`; the wand's tip points LEFT when unrotated.
enum SantaSprites {
    static func makeTextures(device: MTLDevice) -> (body: MTLTexture, wand: MTLTexture)? {
        guard let body = VehicleSprites.texture(device: device, size: CGSize(width: 120, height: 150), draw: drawBody),
              let wand = VehicleSprites.texture(device: device, size: CGSize(width: 64, height: 16), draw: drawWand) else { return nil }
        return (body, wand)
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
    }

    private static func drawBody(_ c: CGContext, _ size: CGSize) {
        let red = rgb(204, 32, 44), darkRed = rgb(150, 18, 30), white = rgb(250, 250, 253)
        let skin = rgb(246, 204, 168), black = rgb(30, 30, 34), gold = rgb(240, 190, 40)
        c.setLineJoin(.round); c.setLineCap(.round)

        // Back arm, trailing.
        c.setStrokeColor(darkRed); c.setLineWidth(11)
        c.move(to: CGPoint(x: 82, y: 98)); c.addLine(to: CGPoint(x: 94, y: 72)); c.strokePath()
        c.setFillColor(white); c.fillEllipse(in: CGRect(x: 88, y: 64, width: 11, height: 11))

        // Legs: flying pose, trailing behind (to the right) with black boots.
        c.setStrokeColor(red); c.setLineWidth(13)
        c.move(to: CGPoint(x: 58, y: 48)); c.addLine(to: CGPoint(x: 82, y: 28)); c.strokePath()
        c.move(to: CGPoint(x: 70, y: 50)); c.addLine(to: CGPoint(x: 98, y: 38)); c.strokePath()
        c.setFillColor(black)
        c.fillEllipse(in: CGRect(x: 78, y: 20, width: 20, height: 11))
        c.fillEllipse(in: CGRect(x: 94, y: 31, width: 20, height: 11))

        // Coat.
        let coat = CGPath(roundedRect: CGRect(x: 40, y: 46, width: 50, height: 66), cornerWidth: 15, cornerHeight: 15, transform: nil)
        c.addPath(coat); c.setFillColor(red); c.fillPath()
        c.addPath(coat); c.setStrokeColor(darkRed); c.setLineWidth(1.5); c.strokePath()
        c.setFillColor(white)
        c.addPath(CGPath(roundedRect: CGRect(x: 38, y: 43, width: 54, height: 9), cornerWidth: 4, cornerHeight: 4, transform: nil)); c.fillPath()
        c.addPath(CGPath(roundedRect: CGRect(x: 37, y: 48, width: 8, height: 60), cornerWidth: 4, cornerHeight: 4, transform: nil)); c.fillPath()
        // Belt + buckle.
        c.setFillColor(black); c.fill(CGRect(x: 40, y: 72, width: 50, height: 9))
        c.setFillColor(gold); c.fill(CGRect(x: 50, y: 70, width: 12, height: 13))
        c.setFillColor(black); c.fill(CGRect(x: 54, y: 74, width: 4, height: 5))

        // Head, beard, face.
        c.setFillColor(skin); c.fillEllipse(in: CGRect(x: 47, y: 109, width: 30, height: 30))
        let beard = CGMutablePath()
        beard.move(to: CGPoint(x: 49, y: 122))
        beard.addCurve(to: CGPoint(x: 54, y: 90), control1: CGPoint(x: 45, y: 108), control2: CGPoint(x: 47, y: 98))
        beard.addCurve(to: CGPoint(x: 72, y: 96), control1: CGPoint(x: 60, y: 82), control2: CGPoint(x: 68, y: 84))
        beard.addCurve(to: CGPoint(x: 77, y: 121), control1: CGPoint(x: 78, y: 104), control2: CGPoint(x: 78, y: 113))
        beard.closeSubpath()
        c.addPath(beard); c.setFillColor(white); c.fillPath()
        c.setFillColor(white); c.fillEllipse(in: CGRect(x: 47, y: 114, width: 18, height: 9))
        c.setFillColor(rgb(236, 130, 120)); c.fillEllipse(in: CGRect(x: 45, y: 118, width: 8, height: 8))
        c.setFillColor(black); c.fillEllipse(in: CGRect(x: 54, y: 126, width: 4, height: 4))
        c.setStrokeColor(white); c.setLineWidth(2)
        c.move(to: CGPoint(x: 51, y: 132)); c.addLine(to: CGPoint(x: 60, y: 133)); c.strokePath()

        // Hat with curled tip and pompom.
        let hat = CGMutablePath()
        hat.move(to: CGPoint(x: 46, y: 131))
        hat.addCurve(to: CGPoint(x: 70, y: 150), control1: CGPoint(x: 50, y: 145), control2: CGPoint(x: 60, y: 150))
        hat.addCurve(to: CGPoint(x: 98, y: 137), control1: CGPoint(x: 84, y: 150), control2: CGPoint(x: 96, y: 146))
        hat.addLine(to: CGPoint(x: 79, y: 131)); hat.closeSubpath()
        c.addPath(hat); c.setFillColor(red); c.fillPath()
        c.addPath(hat); c.setStrokeColor(darkRed); c.setLineWidth(1.2); c.strokePath()
        c.setFillColor(white)
        c.addPath(CGPath(roundedRect: CGRect(x: 43, y: 127, width: 40, height: 9), cornerWidth: 4.5, cornerHeight: 4.5, transform: nil)); c.fillPath()
        c.fillEllipse(in: CGRect(x: 91, y: 131, width: 13, height: 13))

        // Front arm reaching forward (left); the glove at (20, 98) holds the wand.
        c.setStrokeColor(red); c.setLineWidth(12)
        c.move(to: CGPoint(x: 48, y: 100)); c.addLine(to: CGPoint(x: 27, y: 98)); c.strokePath()
        c.setFillColor(white); c.fillEllipse(in: CGRect(x: 23, y: 91, width: 8, height: 14))
        c.fillEllipse(in: CGRect(x: 13.5, y: 91.5, width: 13, height: 13))
    }

    private static func drawWand(_ c: CGContext, _ size: CGSize) {
        c.setLineCap(.round)
        // Handle (right), shaft, gold ring.
        c.setStrokeColor(rgb(96, 60, 34)); c.setLineWidth(5.5)
        c.move(to: CGPoint(x: 44, y: 8)); c.addLine(to: CGPoint(x: 62, y: 8)); c.strokePath()
        c.setStrokeColor(rgb(236, 228, 212)); c.setLineWidth(3.2)
        c.move(to: CGPoint(x: 9, y: 8)); c.addLine(to: CGPoint(x: 44, y: 8)); c.strokePath()
        c.setStrokeColor(rgb(240, 190, 40)); c.setLineWidth(2)
        c.move(to: CGPoint(x: 44, y: 5)); c.addLine(to: CGPoint(x: 44, y: 11)); c.strokePath()
        // Glow at the tip.
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        if let g = CGGradient(colorsSpace: cs, colors: [rgb(255, 235, 150, 0.95), rgb(255, 210, 90, 0)] as CFArray, locations: [0, 1]) {
            c.drawRadialGradient(g, startCenter: CGPoint(x: 7, y: 8), startRadius: 0, endCenter: CGPoint(x: 7, y: 8), endRadius: 8, options: [])
        }
        // Four-point star.
        c.setFillColor(rgb(255, 250, 220))
        let star = CGMutablePath()
        let ctr = CGPoint(x: 7, y: 8)
        for i in 0..<8 {
            let a = CGFloat(i) * .pi / 4
            let r: CGFloat = i % 2 == 0 ? 6 : 1.8
            let pt = CGPoint(x: ctr.x + cos(a) * r, y: ctr.y + sin(a) * r)
            if i == 0 { star.move(to: pt) } else { star.addLine(to: pt) }
        }
        star.closeSubpath()
        c.addPath(star); c.fillPath()
    }
}
