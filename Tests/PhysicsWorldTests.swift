import XCTest
import simd
@testable import Snowfall

final class PhysicsWorldTests: XCTestCase {
    private func quietConfig() -> SimulationConfiguration {
        var c = SimulationConfiguration()
        c.density = 0; c.windStrength = 0; c.turbulence = 0
        return c
    }

    private func particle(at p: SIMD2<Float> = SIMD2(500, 800), v: SIMD2<Float> = .zero) -> SnowParticle {
        var s = SnowParticle.blank
        s.position = p; s.velocity = v; s.mass = 1; s.radius = 2; s.volume = 5
        return s
    }

    func testGravityPullsDownAndApproachesTerminalVelocity() {
        let w = PhysicsWorld(config: quietConfig())
        w.pool.spawn(particle())
        for _ in 0..<1200 { w.step(dt: 1.0 / 120) }   // 10 s
        let p = w.pool[0]
        let terminal = -w.config.gravity * 1 / w.config.baseDrag
        XCTAssertLessThan(p.position.y, 800)
        XCTAssertEqual(p.velocity.y, terminal, accuracy: 1.0)
        XCTAssertEqual(p.velocity.x, 0, accuracy: 1e-3)
    }

    func testWindPushesRight() {
        var c = quietConfig(); c.windStrength = 0.8
        let w = PhysicsWorld(config: c)
        w.pool.spawn(particle())
        for _ in 0..<240 { w.step(dt: 1.0 / 120) }
        XCTAssertGreaterThan(w.pool[0].velocity.x, 20)
    }

    func testDragReducesVelocityWithoutWindOrGravity() {
        var c = quietConfig(); c.gravity = 0
        let w = PhysicsWorld(config: c)
        w.pool.spawn(particle(v: SIMD2(100, 0)))
        for _ in 0..<120 { w.step(dt: 1.0 / 120) }
        XCTAssertLessThan(w.pool[0].velocity.x, 10)
        XCTAssertGreaterThan(w.pool[0].velocity.x, 0)
    }

    func testVelocityIsClamped() {
        let w = PhysicsWorld(config: quietConfig())
        w.pool.spawn(particle(v: SIMD2(1e6, -1e6)))
        w.step(dt: 1.0 / 120)
        XCTAssertLessThanOrEqual(simd_length(w.pool[0].velocity), w.config.maxSpeed + 0.01)
    }

    func testPoolCapacityAndReuse() {
        let pool = ParticlePool(capacity: 3)
        XCTAssertTrue(pool.spawn(.blank)); XCTAssertTrue(pool.spawn(.blank)); XCTAssertTrue(pool.spawn(.blank))
        XCTAssertFalse(pool.spawn(.blank))
        pool.remove(at: 0)
        XCTAssertEqual(pool.count, 2)
        XCTAssertTrue(pool.spawn(.blank))
        XCTAssertEqual(pool.count, 3)
    }

    func testDeterministicSimulation() {
        func run() -> [SIMD2<Float>] {
            var c = SimulationConfiguration(); c.seed = 42; c.density = 1; c.maxParticles = 300
            let w = PhysicsWorld(config: c)
            w.setRegion(CGRect(x: 0, y: 0, width: 1920, height: 1080))
            w.prewarm()
            for _ in 0..<240 { w.step(dt: 1.0 / 120) }
            return (0..<w.pool.count).map { w.pool[$0].position }
        }
        XCTAssertEqual(run(), run())
    }

    func testLargeFrameGapsStayBounded() {
        var c = SimulationConfiguration(); c.density = 1; c.maxParticles = 500
        let w = PhysicsWorld(config: c)
        w.setRegion(CGRect(x: 0, y: 0, width: 1920, height: 1080))
        w.prewarm()
        for _ in 0..<20 { w.step(dt: 0.5) }   // abusive timestep
        for i in 0..<w.pool.count {
            let p = w.pool[i]
            XCTAssertTrue(p.position.x.isFinite && p.position.y.isFinite)
            XCTAssertLessThanOrEqual(simd_length(p.velocity), w.config.maxSpeed + 0.01)
        }
        XCTAssertLessThanOrEqual(w.pool.count, w.pool.capacity)
    }

    func testParticlesDespawnBelowRegion() {
        let w = PhysicsWorld(config: quietConfig())
        w.setRegion(CGRect(x: 0, y: 0, width: 1000, height: 1000))
        w.pool.spawn(particle(at: SIMD2(500, -100)))
        w.step(dt: 1.0 / 120)
        XCTAssertEqual(w.pool.count, 0)
    }

    func testSpawnRespectsTargetAndCapacity() {
        var c = SimulationConfiguration(); c.density = 1; c.maxParticles = 200
        let w = PhysicsWorld(config: c)
        w.setRegion(CGRect(x: 0, y: 0, width: 1920, height: 1080))
        for _ in 0..<(120 * 60) { w.step(dt: 1.0 / 120) }
        XCTAssertLessThanOrEqual(w.pool.count, 200)
        XCTAssertGreaterThan(w.pool.count, 50)
    }

    func testAdaptiveQuality() {
        XCTAssertLessThan(AdaptiveQuality.next(scale: 1, fps: 30, targetFPS: 60, simMs: 1), 1)
        XCTAssertEqual(AdaptiveQuality.next(scale: 0.36, fps: 10, targetFPS: 60, simMs: 1), AdaptiveQuality.minScale)
        XCTAssertGreaterThan(AdaptiveQuality.next(scale: 0.5, fps: 60, targetFPS: 60, simMs: 1), 0.5)
    }

    /// Measured, not asserted: prints simulation cost for a full pool. See docs/TESTING.md.
    func testSimulationStepCost() {
        var c = SimulationConfiguration(); c.density = 1; c.maxParticles = 3000; c.seed = 7
        let w = PhysicsWorld(config: c)
        w.setRegion(CGRect(x: 0, y: 0, width: 3456, height: 2234))
        w.setSurfaces([CollisionSurface(id: "d", frame: CGRect(x: 0, y: 0, width: 3456, height: 0), velocity: .zero, kind: .displayBottom)])
        w.prewarm()
        for _ in 0..<600 { w.step(dt: 1.0 / 120) }
        let n = 1200
        let t0 = ContinuousClock.now
        for _ in 0..<n { w.step(dt: 1.0 / 120) }
        let d = ContinuousClock.now - t0
        let ms = Double(d.components.attoseconds) / 1e15 / Double(n) + Double(d.components.seconds) * 1000 / Double(n)
        print("PERF sim step with \(w.pool.count) particles: \(String(format: "%.4f", ms)) ms/step")
        XCTAssertLessThan(ms, 4)
    }
}

final class ForceFieldTests: XCTestCase {
    private func pointer(_ p: SIMD2<Float> = .zero) -> PointerState {
        PointerState(position: p, velocity: .zero, isActive: true, radius: 100, strength: 2000)
    }

    func testRepelsAwayFromPointer() {
        let a = ForceField.pointerAcceleration(particle: SIMD2(50, 0), pointer: pointer())
        XCTAssertGreaterThan(a.x, 0)
        let b = ForceField.pointerAcceleration(particle: SIMD2(-50, 0), pointer: pointer())
        XCTAssertLessThan(b.x, 0)
    }

    func testUpwardBias() {
        XCTAssertGreaterThan(ForceField.pointerAcceleration(particle: SIMD2(50, 0), pointer: pointer()).y, 0)
    }

    func testFalloffAndRadiusBoundary() {
        let near = simd_length(ForceField.pointerAcceleration(particle: SIMD2(20, 0), pointer: pointer()))
        let far = simd_length(ForceField.pointerAcceleration(particle: SIMD2(80, 0), pointer: pointer()))
        XCTAssertGreaterThan(near, far)
        XCTAssertEqual(ForceField.pointerAcceleration(particle: SIMD2(100, 0), pointer: pointer()), .zero)
        XCTAssertEqual(ForceField.pointerAcceleration(particle: SIMD2(250, 0), pointer: pointer()), .zero)
    }

    func testZeroDistanceIsSafe() {
        let a = ForceField.pointerAcceleration(particle: .zero, pointer: pointer())
        XCTAssertTrue(a.x.isFinite && a.y.isFinite)
    }

    func testImpulseIsBounded() {
        var p = pointer(); p.strength = 1e9; p.velocity = SIMD2(1e9, 1e9)
        let a = ForceField.pointerAcceleration(particle: SIMD2(1, 1), pointer: p)
        XCTAssertLessThanOrEqual(simd_length(a), ForceField.maxPointerAcceleration + 0.01)
    }

    func testInactivePointerDoesNothing() {
        var p = pointer(); p.isActive = false
        XCTAssertEqual(ForceField.pointerAcceleration(particle: SIMD2(10, 0), pointer: p), .zero)
    }

    func testDisturbedParticleReturnsToFalling() {
        var c = SimulationConfiguration(); c.density = 0; c.windStrength = 0; c.turbulence = 0
        let w = PhysicsWorld(config: c)
        w.pointer = pointer(SIMD2(500, 800)); w.pointer.radius = 100
        var s = SnowParticle.blank; s.position = SIMD2(520, 800); s.mass = 1
        w.pool.spawn(s)
        w.step(dt: 1.0 / 120)
        XCTAssertEqual(w.pool[0].state, .disturbed)
        w.pointer.isActive = false
        for _ in 0..<120 { w.step(dt: 1.0 / 120) }
        XCTAssertEqual(w.pool[0].state, .falling)
    }
}
