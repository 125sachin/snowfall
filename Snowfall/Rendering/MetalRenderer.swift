import AppKit
import MetalKit
import simd

enum RendererError: Error, LocalizedError {
    case noDevice, noQueue, library(String), pipeline(String)
    var errorDescription: String? {
        switch self {
        case .noDevice: "No Metal device is available."
        case .noQueue: "Could not create a Metal command queue."
        case .library(let m): "Shader compilation failed: \(m)"
        case .pipeline(let m): "Pipeline creation failed: \(m)"
        }
    }
}

private struct ViewUniforms { var origin: SIMD2<Float>; var size: SIMD2<Float> }
private struct SpriteUniforms { var center: SIMD2<Float>; var size: SIMD2<Float>; var rotation: Float; var alpha: Float = 1 }
private struct SurfaceUniforms {
    var minX: Float; var baseY: Float; var binWidth: Float
    var binCount: UInt32; var heightOffset: UInt32; var maxDepth: Float
    var cornerRadius: Float
}

/// Draws one display's share of the snow. Reads immutable snapshots; never touches physics.
///
/// Buffers: particle instances, surface heights and debug rects. Two sets are allocated once and
/// alternated per frame; a semaphore (signalled by the command buffer's completion handler)
/// guarantees the CPU never rewrites a set the GPU is still reading. Nothing is allocated per frame.
@MainActor
final class MetalRenderer: NSObject, MTKViewDelegate {
    static let maxParticles = 6144
    static let maxHeights = 64 * 1024
    static let maxDebug = 256

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let particlePipeline: MTLRenderPipelineState
    private let surfacePipeline: MTLRenderPipelineState
    private let debugPipeline: MTLRenderPipelineState
    private let spritePipeline: MTLRenderPipelineState
    private let crystalTexture: MTLTexture?
    // Helper artwork is rasterised on first use (a helper that never runs costs no memory) and
    // released again once no helper has been drawn for a while.
    private var jcbTextures: (body: MTLTexture, wheel: MTLTexture)?
    private var santaTextures: (body: MTLTexture, wand: MTLTexture)?
    private var ironTextures: IronManSprites.Textures?
    private var thorTextures: ThorSprites.Textures?
    private var spiderTextures: SpiderSprites.Textures?
    private var lastHelperDraw: CFTimeInterval = 0
    private let inFlight = DispatchSemaphore(value: 2)
    private var ring = 0
    private var particleBuffers: [MTLBuffer] = []
    private var heightBuffers: [MTLBuffer] = []
    private var debugBuffers: [MTLBuffer] = []

    private let provider: () -> RenderSnapshot
    private let monitor: PerformanceMonitor
    /// Global frame of the display this renderer draws (canonical points).
    var displayFrame: CGRect
    var drawsDisplayBorder = false

    init(view: MTKView, displayFrame: CGRect, monitor: PerformanceMonitor,
         provider: @escaping () -> RenderSnapshot) throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw RendererError.noDevice }
        guard let queue = device.makeCommandQueue() else { throw RendererError.noQueue }
        self.device = device
        self.queue = queue
        self.provider = provider
        self.monitor = monitor
        self.displayFrame = displayFrame

        let lib: MTLLibrary
        do {
            lib = try device.makeLibrary(source: ShaderSource.particles + "\n", options: nil)
        } catch { throw RendererError.library(error.localizedDescription) }
        let surfLib: MTLLibrary
        do {
            surfLib = try device.makeLibrary(source: ShaderSource.surface, options: nil)
        } catch { throw RendererError.library(error.localizedDescription) }

        func pipeline(_ vlib: MTLLibrary, _ v: String, _ f: String) throws -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = vlib.makeFunction(name: v)
            d.fragmentFunction = vlib.makeFunction(name: f)
            let c = d.colorAttachments[0]!
            c.pixelFormat = view.colorPixelFormat
            c.isBlendingEnabled = true            // premultiplied alpha
            c.rgbBlendOperation = .add; c.alphaBlendOperation = .add
            c.sourceRGBBlendFactor = .one; c.sourceAlphaBlendFactor = .one
            c.destinationRGBBlendFactor = .oneMinusSourceAlpha; c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            do { return try device.makeRenderPipelineState(descriptor: d) }
            catch { throw RendererError.pipeline(error.localizedDescription) }
        }
        particlePipeline = try pipeline(lib, "particle_vertex", "particle_fragment")
        debugPipeline = try pipeline(lib, "debug_vertex", "debug_fragment")
        surfacePipeline = try pipeline(surfLib, "surface_vertex", "surface_fragment")
        spritePipeline = try pipeline(lib, "sprite_vertex", "sprite_fragment")
        crystalTexture = CrystalSprite.makeTexture(device: device)

        func buf(_ bytes: Int) throws -> MTLBuffer {
            guard let b = device.makeBuffer(length: bytes, options: .storageModeShared) else {
                throw RendererError.pipeline("buffer allocation failed")
            }
            return b
        }
        for _ in 0..<2 {
            particleBuffers.append(try buf(Self.maxParticles * MemoryLayout<RenderParticle>.stride))
            heightBuffers.append(try buf(Self.maxHeights * MemoryLayout<Float>.stride))
            debugBuffers.append(try buf(Self.maxDebug * MemoryLayout<DebugRect>.stride))
        }
        super.init()

        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)   // stay transparent
        view.delegate = self
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let start = CACurrentMediaTimeShim.now()
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let cmd = queue.makeCommandBuffer() else { return }
        guard inFlight.wait(timeout: .now()) == .success else { return }   // never block the main thread
        ring = (ring + 1) % 2
        let pBuf = particleBuffers[ring], hBuf = heightBuffers[ring], dBuf = debugBuffers[ring]
        cmd.addCompletedHandler { [inFlight] _ in inFlight.signal() }

        let snap = provider()
        let f = displayFrame
        let margin: Float = 12
        let minX = Float(f.minX) - margin, maxX = Float(f.maxX) + margin
        let minY = Float(f.minY) - margin, maxY = Float(f.maxY) + margin

        // Particles (culled to this display).
        let pp = pBuf.contents().bindMemory(to: RenderParticle.self, capacity: Self.maxParticles)
        var pc = 0
        for p in snap.particles where p.position.x >= minX && p.position.x <= maxX
            && p.position.y >= minY && p.position.y <= maxY {
            if pc >= Self.maxParticles { break }
            pp[pc] = p; pc += 1
        }

        // Surfaces overlapping this display.
        let hp = hBuf.contents().bindMemory(to: Float.self, capacity: Self.maxHeights)
        var visibleSurfaces: [(RenderSurface, Int)] = []
        var hc = 0
        for s in snap.surfaces {
            let w = Float(s.binCount) * s.binWidth
            guard s.minX < maxX, s.minX + w > minX, s.baseY > minY - s.maxDepth, s.baseY < maxY,
                  hc + s.binCount <= Self.maxHeights else { continue }
            for b in 0..<s.binCount { hp[hc + b] = snap.heights[s.heightOffset + b] }
            visibleSurfaces.append((s, hc))
            hc += s.binCount
        }

        // Debug rects (+ optional display border for geometry validation).
        let dp = dBuf.contents().bindMemory(to: DebugRect.self, capacity: Self.maxDebug)
        var dc = 0
        for r in snap.debugRects where dc < Self.maxDebug - 4 { dp[dc] = r; dc += 1 }
        if drawsDisplayBorder {
            let x = Float(f.minX), y = Float(f.minY), w = Float(f.width), h = Float(f.height)
            let c = SIMD4<Float>(0.2, 0.9, 0.5, 0.8), t: Float = 2
            dp[dc] = DebugRect(rect: SIMD4(x, y, w, t), color: c); dc += 1
            dp[dc] = DebugRect(rect: SIMD4(x, y + h - t, w, t), color: c); dc += 1
            dp[dc] = DebugRect(rect: SIMD4(x, y, t, h), color: c); dc += 1
            dp[dc] = DebugRect(rect: SIMD4(x + w - t, y, t, h), color: c); dc += 1
        }

        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        if let enc = cmd.makeRenderCommandEncoder(descriptor: pass) {
            var u = ViewUniforms(origin: SIMD2(Float(f.minX), Float(f.minY)), size: SIMD2(Float(f.width), Float(f.height)))
            for (s, off) in visibleSurfaces {
                var su = SurfaceUniforms(minX: s.minX, baseY: s.baseY, binWidth: s.binWidth,
                                         binCount: UInt32(s.binCount), heightOffset: UInt32(off), maxDepth: s.maxDepth,
                                         cornerRadius: s.cornerRadius)
                enc.setRenderPipelineState(surfacePipeline)
                enc.setVertexBuffer(hBuf, offset: 0, index: 0)
                enc.setVertexBytes(&su, length: MemoryLayout<SurfaceUniforms>.stride, index: 1)
                enc.setVertexBytes(&u, length: MemoryLayout<ViewUniforms>.stride, index: 2)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: s.binCount * 12)
            }
            let anyHelper = !(snap.vehicles.isEmpty && snap.santas.isEmpty && snap.spiders.isEmpty
                              && snap.thors.isEmpty && snap.ironMen.isEmpty)
            if anyHelper { lastHelperDraw = CACurrentMediaTime() }
            if !snap.vehicles.isEmpty {
                if jcbTextures == nil { jcbTextures = VehicleSprites.makeTextures(device: device) }
                if let t = jcbTextures {
                    for v in snap.vehicles { drawVehicle(v, body: t.body, wheel: t.wheel, encoder: enc, uniforms: &u, frame: f) }
                }
            }
            if !snap.santas.isEmpty {
                if santaTextures == nil, let t = SantaSprites.makeTextures(device: device) { santaTextures = (t.body, t.wand) }
                if let t = santaTextures {
                    for sa in snap.santas { drawSanta(sa, body: t.body, wand: t.wand, encoder: enc, uniforms: &u, frame: f) }
                }
            }
            if !snap.spiders.isEmpty {
                if spiderTextures == nil { spiderTextures = SpiderSprites.makeTextures(device: device) }
                if let tex = spiderTextures { for sp in snap.spiders { drawSpider(sp, textures: tex, encoder: enc, uniforms: &u, frame: f) } }
            }
            if !snap.thors.isEmpty {
                if thorTextures == nil { thorTextures = ThorSprites.makeTextures(device: device) }
                if let tex = thorTextures { for th in snap.thors { drawThor(th, textures: tex, encoder: enc, uniforms: &u, frame: f) } }
            }
            if !snap.ironMen.isEmpty {
                if ironTextures == nil { ironTextures = IronManSprites.makeTextures(device: device) }
                if let tex = ironTextures { for m in snap.ironMen { drawIronMan(m, textures: tex, encoder: enc, uniforms: &u, frame: f) } }
            }
            if !anyHelper, lastHelperDraw > 0, CACurrentMediaTime() - lastHelperDraw > 20 {
                jcbTextures = nil; santaTextures = nil; ironTextures = nil; thorTextures = nil; spiderTextures = nil
                lastHelperDraw = 0
            }
            if pc > 0 {
                enc.setRenderPipelineState(particlePipeline)
                enc.setFragmentTexture(crystalTexture, index: 0)
                enc.setVertexBuffer(pBuf, offset: 0, index: 0)
                enc.setVertexBytes(&u, length: MemoryLayout<ViewUniforms>.stride, index: 1)
                enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: pc)
            }
            if dc > 0 {
                enc.setRenderPipelineState(debugPipeline)
                enc.setVertexBuffer(dBuf, offset: 0, index: 0)
                enc.setVertexBytes(&u, length: MemoryLayout<ViewUniforms>.stride, index: 1)
                enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: dc)
            }
            enc.endEncoding()
        }
        cmd.present(drawable)
        cmd.commit()
        monitor.recordRenderFrame(cpuMs: (CACurrentMediaTimeShim.now() - start) * 1000)
    }

    private func drawSprite(_ tex: MTLTexture, encoder enc: MTLRenderCommandEncoder, uniforms u: inout ViewUniforms,
                            cx: Float, cy: Float, w: Float, h: Float, rot: Float, alpha: Float = 1) {
        var s = SpriteUniforms(center: SIMD2(cx, cy), size: SIMD2(w, h), rotation: rot, alpha: alpha)
        enc.setVertexBytes(&s, length: MemoryLayout<SpriteUniforms>.stride, index: 0)
        enc.setVertexBytes(&u, length: MemoryLayout<ViewUniforms>.stride, index: 1)
        enc.setFragmentTexture(tex, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    private func drawThread(_ tex: MTLTexture, from a: SIMD2<Float>, to b: SIMD2<Float>, thickness: Float, alpha: Float,
                            encoder enc: MTLRenderCommandEncoder, uniforms u: inout ViewUniforms, frame f: CGRect) {
        let minX = min(a.x, b.x), maxX = max(a.x, b.x), minY = min(a.y, b.y), maxY = max(a.y, b.y)
        guard maxX > Float(f.minX), minX < Float(f.maxX), maxY > Float(f.minY), minY < Float(f.maxY) else { return }
        let d = b - a
        let len = simd_length(d)
        guard len > 2 else { return }
        let mid = (a + b) / 2
        drawSprite(tex, encoder: enc, uniforms: &u, cx: mid.x, cy: mid.y, w: len, h: thickness, rot: atan2(d.y, d.x), alpha: alpha)
    }

    private func drawSpider(_ s: RenderSpider, textures tex: SpiderSprites.Textures,
                            encoder enc: MTLRenderCommandEncoder, uniforms u: inout ViewUniforms, frame f: CGRect) {
        let k = SpiderMetrics.scale
        let w = SpiderMetrics.width * k, h = SpiderMetrics.height * k
        enc.setRenderPipelineState(spritePipeline)
        // Web patches on piles (side view: squashed discs).
        for p in s.patches where p.x + p.radius > Float(f.minX) && p.x - p.radius < Float(f.maxX) && p.y > Float(f.minY) - 40 && p.y < Float(f.maxY) {
            drawSprite(tex.web, encoder: enc, uniforms: &u, cx: p.x, cy: p.y + p.radius * 0.18, w: p.radius * 2, h: p.radius * 1.2, rot: 0, alpha: p.alpha)
        }
        // Net spun in the air.
        if s.netAlpha > 0.01, s.netRadius > 1 {
            let c = s.netCenter, r = s.netRadius
            if c.x + r > Float(f.minX), c.x - r < Float(f.maxX), c.y + r > Float(f.minY), c.y - r < Float(f.maxY) {
                drawSprite(tex.web, encoder: enc, uniforms: &u, cx: c.x, cy: c.y, w: r * 2, h: r * 2, rot: s.rot, alpha: s.netAlpha)
            }
        }
        // Web threads: to the anchor, to flying web balls, and the tug lines of a yank.
        if s.attached { drawThread(tex.thread, from: s.hand, to: s.anchor, thickness: 3.2, alpha: 0.95, encoder: enc, uniforms: &u, frame: f) }
        for b in s.balls { drawThread(tex.thread, from: s.hand, to: b.pos, thickness: 2.4, alpha: 0.8, encoder: enc, uniforms: &u, frame: f) }
        for p in s.pulls { drawThread(tex.thread, from: s.hand, to: p.to, thickness: 3.0, alpha: p.alpha, encoder: enc, uniforms: &u, frame: f) }
        for b in s.balls {
            drawSprite(tex.ball, encoder: enc, uniforms: &u, cx: b.pos.x, cy: b.pos.y, w: 18, h: 18, rot: 0)
        }
        if s.x + w > Float(f.minX) && s.x - w < Float(f.maxX) && s.y + h > Float(f.minY) && s.y - h < Float(f.maxY) {
            drawSprite(tex.body, encoder: enc, uniforms: &u, cx: s.x, cy: s.y, w: w, h: h, rot: s.rot)
        }
    }

    private func drawThor(_ t: RenderThor, textures tex: ThorSprites.Textures,
                          encoder enc: MTLRenderCommandEncoder, uniforms u: inout ViewUniforms, frame f: CGRect) {
        let k = ThorMetrics.scale
        let w = ThorMetrics.width * k, h = ThorMetrics.height * k
        enc.setRenderPipelineState(spritePipeline)
        // Cracks and shockwave lie on the ground: squashed ellipses (side view).
        for c in t.cracks where c.x + c.radius > Float(f.minX) && c.x - c.radius < Float(f.maxX) && c.y > Float(f.minY) - 40 && c.y < Float(f.maxY) {
            drawSprite(tex.crack, encoder: enc, uniforms: &u, cx: c.x, cy: c.y + 4, w: c.radius * 2, h: c.radius * 0.55, rot: 0, alpha: c.alpha)
        }
        for r in t.rings where r.radius > 1 && r.x + r.radius > Float(f.minX) && r.x - r.radius < Float(f.maxX) {
            drawSprite(tex.ring, encoder: enc, uniforms: &u, cx: r.x, cy: r.y + 6, w: r.radius * 2, h: r.radius * 0.5, rot: 0, alpha: r.alpha)
            drawSprite(tex.ring, encoder: enc, uniforms: &u, cx: r.x, cy: r.y + r.radius * 0.35, w: r.radius * 1.2, h: r.radius * 1.2, rot: 0, alpha: r.alpha * 0.5)
        }
        // Thor and Mjolnir.
        if t.x + w > Float(f.minX) && t.x - w < Float(f.maxX) && t.y + h > Float(f.minY) && t.y < Float(f.maxY) {
            drawSprite(tex.body, encoder: enc, uniforms: &u, cx: t.x, cy: t.y + h / 2, w: w, h: h, rot: t.tilt)
            let left = t.x - w / 2
            var hand = SIMD2(left + ThorMetrics.hand.x * k, t.y + ThorMetrics.hand.y * k)
            if t.tilt != 0 {                                    // the hand rotates with the body about its centre
                let c = SIMD2(t.x, t.y + h / 2), o = hand - c
                hand = c + SIMD2(o.x * cos(t.tilt) - o.y * sin(t.tilt), o.x * sin(t.tilt) + o.y * cos(t.tilt))
            }
            let dir = SIMD2(-cos(t.hammerAngle), -sin(t.hammerAngle))
            let c = hand + dir * (ThorMetrics.pivotToCenter * k)
            drawSprite(tex.hammer, encoder: enc, uniforms: &u, cx: c.x, cy: c.y,
                       w: ThorMetrics.hammerSize.x * k, h: ThorMetrics.hammerSize.y * k, rot: t.hammerAngle)
        }
        // Lightning bolt: glow underneath, white-hot core on top.
        if t.bolt.count > 1 {
            for (a, b) in zip(t.bolt, t.bolt.dropFirst()) {
                let d = b - a
                let len = simd_length(d) + 3
                guard len > 3 else { continue }
                let mid = (a + b) / 2
                let ang = atan2(d.y, d.x)
                drawSprite(tex.bolt, encoder: enc, uniforms: &u, cx: mid.x, cy: mid.y, w: len, h: 30, rot: ang, alpha: t.boltAlpha)
                drawSprite(tex.bolt, encoder: enc, uniforms: &u, cx: mid.x, cy: mid.y, w: len, h: 9, rot: ang, alpha: t.boltAlpha)
            }
        }
        if t.flash > 0.02 {
            let s = 190 * t.flash + 40
            drawSprite(tex.glow, encoder: enc, uniforms: &u, cx: t.flashPos.x, cy: t.flashPos.y + 10, w: s, h: s, rot: 0, alpha: min(1, t.flash))
        }
    }

    private func drawIronMan(_ m: RenderIronMan, textures t: IronManSprites.Textures,
                             encoder enc: MTLRenderCommandEncoder, uniforms u: inout ViewUniforms, frame f: CGRect) {
        let k = IronManMetrics.scale
        let w = IronManMetrics.width * k, h = IronManMetrics.height * k
        let visibleBody = m.x + w > Float(f.minX) && m.x - w < Float(f.maxX) && m.y + h > Float(f.minY) && m.y < Float(f.maxY)
        enc.setRenderPipelineState(spritePipeline)
        if m.firing {
            // Two beams (soft glow underneath, bright core on top), each drawn if it touches this display.
            for b in [m.spot, m.spot2] {
                let a = m.eye
                let minX = min(a.x, b.x), maxX = max(a.x, b.x), minY = min(a.y, b.y), maxY = max(a.y, b.y)
                guard maxX > Float(f.minX), minX < Float(f.maxX), maxY > Float(f.minY), minY < Float(f.maxY) else { continue }
                let d = b - a
                let len = simd_length(d)
                let ang = atan2(d.y, d.x)
                let mid = (a + b) / 2
                drawSprite(t.beam, encoder: enc, uniforms: &u, cx: mid.x, cy: mid.y, w: len, h: 22 * m.intensity, rot: ang)
                drawSprite(t.beam, encoder: enc, uniforms: &u, cx: mid.x, cy: mid.y, w: len, h: 7 * m.intensity, rot: ang)
                drawSprite(t.glow, encoder: enc, uniforms: &u, cx: b.x, cy: b.y, w: 78 * m.intensity, h: 78 * m.intensity, rot: 0)
            }
            drawSprite(t.glow, encoder: enc, uniforms: &u, cx: m.eye.x, cy: m.eye.y, w: 30 * m.intensity, h: 30 * m.intensity, rot: 0)
        }
        if visibleBody {
            drawSprite(t.body, encoder: enc, uniforms: &u, cx: m.x, cy: m.y + m.bob + h / 2, w: w, h: h, rot: IronManMetrics.tilt)
        }
    }

    private func drawSanta(_ s: RenderSanta, body: MTLTexture, wand: MTLTexture,
                           encoder enc: MTLRenderCommandEncoder, uniforms u: inout ViewUniforms, frame f: CGRect) {
        let k = SantaMetrics.scale
        let w = SantaMetrics.width * k, h = SantaMetrics.height * k
        guard s.x + w > Float(f.minX), s.x - w < Float(f.maxX), s.y + h > Float(f.minY), s.y < Float(f.maxY) else { return }
        let left = s.x - w / 2, bottom = s.y + s.bob
        enc.setRenderPipelineState(spritePipeline)
        drawSprite(body, encoder: enc, uniforms: &u, cx: left + w / 2, cy: bottom + h / 2, w: w, h: h, rot: 0)
        let hand = SIMD2(left + SantaMetrics.hand.x * k, bottom + SantaMetrics.hand.y * k)
        let dir = SIMD2(-cos(s.wandAngle), -sin(s.wandAngle))
        let c = hand + dir * (SantaMetrics.wandPivotToCenter * k)
        drawSprite(wand, encoder: enc, uniforms: &u, cx: c.x, cy: c.y,
                   w: SantaMetrics.wandSize.x * k, h: SantaMetrics.wandSize.y * k, rot: s.wandAngle)
    }

    private func drawVehicle(_ v: RenderVehicle, body: MTLTexture, wheel: MTLTexture,
                             encoder enc: MTLRenderCommandEncoder, uniforms u: inout ViewUniforms, frame f: CGRect) {
        let k = PlowVehicle.spriteScale
        let left = v.bladeX - 2 * k
        let right = left + Float(VehicleSprites.bodySize.width) * k
        guard right > Float(f.minX), left < Float(f.maxX), v.groundY >= Float(f.minY) - 120, v.groundY <= Float(f.maxY) else { return }
        let gy = v.groundY + v.bob
        enc.setRenderPipelineState(spritePipeline)
        func draw(_ tex: MTLTexture, cx: Float, cy: Float, w: Float, h: Float, rot: Float) {
            var s = SpriteUniforms(center: SIMD2(cx, cy), size: SIMD2(w, h), rotation: rot)
            enc.setVertexBytes(&s, length: MemoryLayout<SpriteUniforms>.stride, index: 0)
            enc.setVertexBytes(&u, length: MemoryLayout<ViewUniforms>.stride, index: 1)
            enc.setFragmentTexture(tex, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        let bw = Float(VehicleSprites.bodySize.width) * k, bh = Float(VehicleSprites.bodySize.height) * k
        draw(body, cx: left + bw / 2, cy: gy + bh / 2, w: bw, h: bh, rot: 0)
        for w in [VehicleSprites.rearWheel, VehicleSprites.frontWheel] {
            let d = Float(w.r) * 2 * k
            draw(wheel, cx: left + Float(w.x) * k, cy: gy + Float(w.y) * k, w: d, h: d, rot: v.wheelAngle)
        }
    }
}
