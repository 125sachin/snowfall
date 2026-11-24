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
private struct SurfaceUniforms {
    var minX: Float; var baseY: Float; var binWidth: Float
    var binCount: UInt32; var heightOffset: UInt32; var maxDepth: Float
}

/// Draws one display's share of the snow. Reads immutable snapshots; never touches physics.
///
/// Buffers: particle instances, surface heights and debug rects. Two sets are allocated once and
/// alternated per frame; a semaphore (signalled by the command buffer's completion handler)
/// guarantees the CPU never rewrites a set the GPU is still reading. Nothing is allocated per frame.
@MainActor
final class MetalRenderer: NSObject, MTKViewDelegate {
    static let maxParticles = 4096
    static let maxHeights = 64 * 1024
    static let maxDebug = 256

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let particlePipeline: MTLRenderPipelineState
    private let surfacePipeline: MTLRenderPipelineState
    private let debugPipeline: MTLRenderPipelineState
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
                                         binCount: UInt32(s.binCount), heightOffset: UInt32(off), maxDepth: s.maxDepth)
                enc.setRenderPipelineState(surfacePipeline)
                enc.setVertexBuffer(hBuf, offset: 0, index: 0)
                enc.setVertexBytes(&su, length: MemoryLayout<SurfaceUniforms>.stride, index: 1)
                enc.setVertexBytes(&u, length: MemoryLayout<ViewUniforms>.stride, index: 2)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: s.binCount * 12)
            }
            if pc > 0 {
                enc.setRenderPipelineState(particlePipeline)
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
}
