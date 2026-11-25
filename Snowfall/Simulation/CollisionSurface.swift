import Foundation
import simd

enum SurfaceKind: Sendable { case displayBottom, windowTop }

/// Immutable surface description passed into the simulation. `frame` is in canonical global
/// points; the collidable edge is `frame.maxY` (the top edge), spanning `minX...maxX`.
struct CollisionSurface: Identifiable, Equatable, Sendable {
    let id: String
    let frame: CGRect
    let velocity: CGVector
    let kind: SurfaceKind
    /// Stacking order: 0 = frontmost window. Display floors use Int.max.
    var zRank: Int = Int.max
    /// Radius of the window's rounded top corners (pt). Snow follows the curve instead of
    /// floating over the corner gap. 0 for display floors.
    var cornerRadius: Float = 0

    var topY: Float { Float(frame.maxY) }

    /// How far the surface lies below `topY` at surface-local x (0 on the flat part, `cornerRadius`
    /// at the very edge): a quarter-circle at each end, clamped so tiny windows stay valid.
    func drop(atLocalX x: Float) -> Float {
        let w = Float(frame.width)
        let r = min(cornerRadius, w / 2)
        guard r > 0 else { return 0 }
        let d = min(x, w - x)
        guard d < r else { return 0 }
        let dd = max(d, 0)
        return r - (r * r - (r - dd) * (r - dd)).squareRoot()
    }

    /// Height of the (snow-free) surface at global x.
    func topY(atX x: Float) -> Float { topY - drop(atLocalX: x - minX) }
    var minX: Float { Float(frame.minX) }
    var maxX: Float { Float(frame.maxX) }
}

enum CollisionOutcome: Equatable { case bounced, rested }

enum CollisionSolver {
    /// Resolves a particle that has crossed a horizontal surface at `surfaceY`.
    /// Vertical velocity is reflected with `restitution`; tangential velocity is damped
    /// toward the surface velocity by `friction` (so moving surfaces drag contacting snow).
    static func resolve(particle p: inout SnowParticle, surfaceY: Float, surfaceVelocity: SIMD2<Float>,
                        restitution: Float, friction: Float, restSpeed: Float) -> CollisionOutcome {
        p.position.y = surfaceY
        let rel = p.velocity - surfaceVelocity
        let approach = min(rel.y, 0)
        let bounceVy = -approach * restitution
        let tangential = rel.x * (1 - friction)
        p.velocity = surfaceVelocity + SIMD2(tangential, bounceVy)
        return bounceVy < restSpeed ? .rested : .bounced
    }
}

/// Uniform x-bucket broad phase. Rebuilt only when the surface set changes.
struct SurfaceIndex {
    static let bucketWidth: Float = 128
    private var firstBucket = 0
    private var buckets: [[Int]] = []

    mutating func rebuild(spans: [(minX: Float, maxX: Float)]) {
        buckets.removeAll(keepingCapacity: true)
        guard !spans.isEmpty else { return }
        let lo = spans.map { Int(floor($0.minX / Self.bucketWidth)) }.min()!
        let hi = spans.map { Int(floor($0.maxX / Self.bucketWidth)) }.max()!
        firstBucket = lo
        buckets = Array(repeating: [], count: hi - lo + 1)
        for (i, s) in spans.enumerated() {
            let a = Int(floor(s.minX / Self.bucketWidth)) - lo
            let b = Int(floor(s.maxX / Self.bucketWidth)) - lo
            for k in a...b { buckets[k].append(i) }
        }
    }

    @inline(__always)
    func candidates(x: Float) -> [Int] {
        let k = Int(floor(x / Self.bucketWidth)) - firstBucket
        guard k >= 0, k < buckets.count else { return [] }
        return buckets[k]
    }
}
