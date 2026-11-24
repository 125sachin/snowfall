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

struct RenderVehicle: Sendable {
    var bladeX: Float        // world x of the blade face (vehicle front, facing left)
    var groundY: Float
    var wheelAngle: Float    // radians, counter-clockwise when driving left
    var bob: Float
}

struct RenderSanta: Sendable {
    var x: Float          // sprite centre x
    var y: Float          // sprite bottom y
    var bob: Float
    var wandAngle: Float  // radians; 0 = pointing left, negative = raised
}

struct RenderIronMan: Sendable {
    var x: Float          // sprite centre x
    var y: Float          // sprite bottom y
    var bob: Float
    var firing: Bool
    var eye: SIMD2<Float>
    var spot: SIMD2<Float>
    var spot2: SIMD2<Float>
    var intensity: Float
}

struct RenderRing: Sendable { var x: Float; var y: Float; var radius: Float; var alpha: Float }
struct RenderCrack: Sendable { var x: Float; var y: Float; var radius: Float; var alpha: Float; var seed: Float }

struct RenderThor: Sendable {
    var x: Float              // sprite centre x
    var y: Float              // sprite bottom y
    var tilt: Float
    var hammerAngle: Float    // radians; 0 = pointing left, positive = down, negative = raised
    var bolt: [SIMD2<Float>]  // jagged lightning polyline (empty when none)
    var boltAlpha: Float
    var rings: [RenderRing]
    var cracks: [RenderCrack]
    var flash: Float
    var flashPos: SIMD2<Float>
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
    var vehicles: [RenderVehicle] = []
    var santas: [RenderSanta] = []
    var ironMen: [RenderIronMan] = []
    var thors: [RenderThor] = []
    var stats = SimulationStats()
}
