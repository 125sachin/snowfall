import Foundation
import simd

/// Units: points (pt) and seconds. Canonical space is global AppKit points:
/// origin bottom-left of the primary display, +y up.
enum ParticleState: UInt8, Sendable {
    case falling
    case disturbed   // recently pushed by the pointer
    case displaced   // snow shed from a moving/closing window or an overflowing edge
}

struct SnowParticle: Sendable {
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
    var radius: Float
    var rotation: Float
    var angularVelocity: Float
    var opacity: Float
    /// Drag response factor. Heavier particles fall faster (terminal speed ∝ mass).
    var mass: Float
    /// Snow volume (pt²) deposited into a height field on landing.
    var volume: Float
    var stateTime: Float
    var state: ParticleState

    static let blank = SnowParticle(position: .zero, velocity: .zero, radius: 1, rotation: 0,
                                    angularVelocity: 0, opacity: 1, mass: 1, volume: 0,
                                    stateTime: 0, state: .falling)
}

/// Deterministic SplitMix64 generator for reproducible simulation in tests.
struct SeededRNG: RandomNumberGenerator, Sendable {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func float(_ range: ClosedRange<Float>) -> Float {
        Float.random(in: range, using: &self)
    }
}

/// Fixed-capacity particle storage. All memory is allocated once; spawn/remove never allocate.
/// Not thread-safe: owned by the simulation queue.
final class ParticlePool {
    let capacity: Int
    private(set) var count = 0
    let base: UnsafeMutablePointer<SnowParticle>

    init(capacity: Int) {
        self.capacity = max(1, capacity)
        base = .allocate(capacity: self.capacity)
        base.initialize(repeating: .blank, count: self.capacity)
    }

    deinit {
        base.deinitialize(count: capacity)
        base.deallocate()
    }

    @discardableResult
    func spawn(_ p: SnowParticle) -> Bool {
        guard count < capacity else { return false }
        base[count] = p
        count += 1
        return true
    }

    /// Swap-remove. The element previously last now occupies `index`.
    func remove(at index: Int) {
        precondition(index >= 0 && index < count)
        count -= 1
        if index != count { base[index] = base[count] }
    }

    func removeAll() { count = 0 }

    subscript(i: Int) -> SnowParticle {
        get { base[i] }
        set { base[i] = newValue }
    }
}

struct PointerState: Sendable, Equatable {
    var position: SIMD2<Float> = .zero
    var velocity: SIMD2<Float> = .zero
    var isActive = false
    var radius: Float = 120
    /// Peak radial acceleration (pt/s²) at the pointer centre.
    var strength: Float = 2500
}

struct SimulationConfiguration: Sendable, Equatable {
    var gravity: Float = 260
    var baseDrag: Float = 3.2
    var windMaxSpeed: Float = 240
    var turbulence: Float = 14
    var maxSpeed: Float = 900
    var fixedTimestep: Float = 1.0 / 120.0
    var maxSubsteps = 8
    var maxElapsed: Double = 0.25

    var density: Float = 0.5
    var densityScale: Float = 1
    var maxParticles = 2000
    var windStrength: Float = 0.25
    var fallSpeedScale: Float = 1
    var opacityScale: Float = 1
    var minRadius: Float = 2.0
    var maxRadius: Float = 5.6
    /// Extra pool slots reserved for displaced clusters and edge overflow.
    var spawnReserve = 256

    var restitution: Float = 0.05
    var friction: Float = 0.6
    var restSpeed: Float = 35

    var accumulationEnabled = true
    var displayMaxDepth: Float = 30
    var windowMaxDepth: Float = 14
    /// Snow volume = compaction · π r².
    var compaction: Float = 0.18

    var windowPhysicsEnabled = false
    /// Window speed (pt/s) below which snow is fully carried along.
    var windowStickSpeed: Float = 350
    var maxDisplacementClusters = 24

    // Snow plow (JCB). Units: pt, s. Terminal speed unloaded = engine / drag = 90 pt/s.
    var plowAuto = true
    var plowInterval: Float = 180
    var plowEngineForce: Float = 36
    var plowDrag: Float = 0.4
    var plowLoadResistance: Float = 0.006    // force per pt² of pushed snow (saturates at 2× capacity)
    var plowMinSpeed: Float = 18
    var plowCapacity: Float = 1500           // pt² the blade can carry before snow spills over
    var plowResidueDepth: Float = 1.0

    var seed: UInt64 = 1

    var poolCapacity: Int { maxParticles + spawnReserve }
}
