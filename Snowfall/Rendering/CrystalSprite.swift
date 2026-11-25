import AppKit
import Metal

/// Alternative flake shape loaded from the bundled `crystal.svg` and rasterised once to a white
/// alpha mask. If the file cannot be loaded the shader's procedural flake is used for every particle.
enum CrystalSprite {
    static let pixelSize = 128

    static func makeTexture(device: MTLDevice) -> MTLTexture? {
        guard let url = Bundle.main.url(forResource: "crystal", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else { return nil }
        let n = pixelSize
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: cs, bitmapInfo: info) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: n, height: n).insetBy(dx: 2, dy: 2)
        var proposed = rect
        guard let cg = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else { return nil }
        ctx.setShouldAntialias(true); ctx.interpolationQuality = .high
        ctx.draw(cg, in: rect)
        ctx.setBlendMode(.sourceIn)                       // recolour the black artwork white
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: n, height: n))
        guard let data = ctx.data else { return nil }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: n, height: n, mipmapped: true)
        d.usage = .shaderRead
        guard let t = device.makeTexture(descriptor: d) else { return nil }
        t.replace(region: MTLRegionMake2D(0, 0, n, n), mipmapLevel: 0, withBytes: data, bytesPerRow: n * 4)
        if let q = device.makeCommandQueue(), let cmd = q.makeCommandBuffer(), let blit = cmd.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: t); blit.endEncoding(); cmd.commit(); cmd.waitUntilCompleted()
        }
        return t
    }
}
