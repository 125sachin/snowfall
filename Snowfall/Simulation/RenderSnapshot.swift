import Foundation
import simd

/// Layout matches `ParticleInstance` in the Metal source (24 bytes).
struct RenderParticle: Sendable {
    var position: SIMD2<Float>
    var radius: Float
    var rotation: Float
    var opacity: Float
    var seed: Float
}

struct RenderSurface: Sendable {
    var minX: Float
    var baseY: Float
    var binWidth: Float
    var binCount: Int
    var heightOffset: Int
    var maxDepth: Float
}

/// Layout matches `DebugRect` in the Metal source (32 bytes): rect = (x, y, w, h), then colour.
struct DebugRect: Sendable {
    var rect: SIMD4<Float>
    var color: SIMD4<Float>
}

struct SimulationStats: Sendable, Equatable {
    var particleCount = 0
    var surfaceCount = 0
    var windowSurfaceCount = 0
    var simStepMs: Double = 0
    var settledVolume: Float = 0
    var clippedVolume: Float = 0
    var droppedVolume: Float = 0
    var densityScale: Float = 1
}

/// Immutable-by-convention frame of data handed from the simulation queue to renderers.
struct RenderSnapshot: Sendable {
    var sequence: UInt64 = 0
    var particles: [RenderParticle] = []
    var surfaces: [RenderSurface] = []
    var heights: [Float] = []
    var debugRects: [DebugRect] = []
    var stats = SimulationStats()
}
