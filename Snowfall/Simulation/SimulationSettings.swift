import Foundation

/// Sendable bundle of everything the simulation needs from user settings and runtime state.
struct SimulationSettings: Sendable, Equatable {
    var running = true
    var density: Double = 0.5
    var wind: Double = 0.25
    var fallSpeed: Double = 1
    var opacity: Double = 1
    var maxParticles = 2000
    var accumulation = true
    var maxDepth: Double = 0.5
    var pointerEnabled = true
    var pointerRadius: Double = 120
    var pointerStrength: Double = 0.5
    var windowPhysics = false
    var displacementStrength: Double = 0.5
    var lowPower = false
    var showSurfaces = false
    var plowAuto = true
    var plowIntervalSeconds: Double = 180

    func configuration(base: SimulationConfiguration, densityScale: Float) -> SimulationConfiguration {
        var c = base
        let lp: Float = lowPower ? 0.5 : 1
        c.density = Float(density)
        c.densityScale = densityScale * lp
        c.windStrength = Float(wind)
        c.fallSpeedScale = Float(fallSpeed)
        c.opacityScale = Float(opacity)
        c.maxParticles = maxParticles
        c.accumulationEnabled = accumulation
        c.displayMaxDepth = Float(10 + maxDepth * 50)
        c.windowMaxDepth = Float(6 + maxDepth * 20)
        c.windowPhysicsEnabled = windowPhysics
        c.plowAuto = plowAuto
        c.plowInterval = Float(plowIntervalSeconds)
        c.windowStickSpeed = Float(700 - displacementStrength * 550)
        return c
    }
}

struct PointerSample: Sendable, Equatable {
    var x: Float
    var y: Float
    var vx: Float
    var vy: Float
}

/// Adapts particle density to observed frame rate. Pure so it can be tested.
enum AdaptiveQuality {
    static let minScale: Float = 0.35
    static func next(scale: Float, fps: Double, targetFPS: Double, simMs: Double) -> Float {
        guard fps > 0 else { return scale }
        if fps < targetFPS * 0.85 || simMs > 1000 / targetFPS * 0.5 {
            return max(minScale, scale - 0.1)
        }
        if fps >= targetFPS * 0.97 { return min(1, scale + 0.03) }
        return scale
    }
}
