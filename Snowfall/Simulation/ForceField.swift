import Foundation
import simd

/// Pure force functions, independent of the pool so they can be unit tested.
struct ForceField: Sendable {
    var windStrength: Float
    var windMaxSpeed: Float
    var turbulence: Float

    /// Air velocity (pt/s) at a position. Horizontal wind with slow gusts plus smooth,
    /// low-amplitude turbulence built from low-frequency sines (no per-frame jitter).
    func airVelocity(at p: SIMD2<Float>, time t: Float) -> SIMD2<Float> {
        let gust = 1 + 0.45 * sin(0.21 * t + 0.7) + 0.25 * sin(0.57 * t + 2.1)
        let base = windStrength * windMaxSpeed * gust
        let tx = turbulence * (sin(p.y * 0.011 + t * 0.7) + 0.6 * sin(p.x * 0.007 - t * 0.4 + 1.3))
        let ty = turbulence * 0.4 * sin(p.x * 0.013 + t * 0.5 + 0.4)
        return SIMD2(base + tx, ty)
    }

    static let maxPointerAcceleration: Float = 6000
    static let swirl: Float = 0.35
    static let upwardBias: Float = 0.25

    /// Acceleration (pt/s²) applied to a particle by the pointer. Zero outside the radius.
    /// Radial repulsion with quadratic falloff, small upward bias, tangential swirl, and a
    /// fraction of pointer velocity so a sweeping cursor carries snow along.
    static func pointerAcceleration(particle: SIMD2<Float>, pointer: PointerState) -> SIMD2<Float> {
        guard pointer.isActive, pointer.radius > 0 else { return .zero }
        let d = particle - pointer.position
        let dist = simd_length(d)
        guard dist.isFinite, dist < pointer.radius else { return .zero }
        let dir: SIMD2<Float> = dist > 1e-4 ? d / dist : SIMD2(0, 1)
        let t = 1 - dist / pointer.radius
        let falloff = t * t
        let s = pointer.strength * falloff
        var a = dir * s
        a.y += upwardBias * s
        a += SIMD2(-dir.y, dir.x) * (swirl * s)
        a += pointer.velocity * (0.8 * falloff)
        let len = simd_length(a)
        if len > maxPointerAcceleration { a *= maxPointerAcceleration / len }
        return a
    }
}
