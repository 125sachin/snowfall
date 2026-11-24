import XCTest
import simd
@testable import Snowfall

final class CollisionSolverTests: XCTestCase {
    private func falling(vy: Float, vx: Float = 0) -> SnowParticle {
        var p = SnowParticle.blank
        p.position = SIMD2(0, -1); p.velocity = SIMD2(vx, vy)
        return p
    }

    func testLowRestitutionRests() {
        var p = falling(vy: -80)
        let o = CollisionSolver.resolve(particle: &p, surfaceY: 0, surfaceVelocity: .zero, restitution: 0.05, friction: 0.6, restSpeed: 35)
        XCTAssertEqual(o, .rested)
        XCTAssertEqual(p.position.y, 0)
    }

    func testBounceReflectsVelocity() {
        var p = falling(vy: -500)
        let o = CollisionSolver.resolve(particle: &p, surfaceY: 0, surfaceVelocity: .zero, restitution: 0.5, friction: 0, restSpeed: 35)
        XCTAssertEqual(o, .bounced)
        XCTAssertEqual(p.velocity.y, 250, accuracy: 0.01)
    }

    func testFrictionDampsTangentialVelocity() {
        var p = falling(vy: -100, vx: 100)
        _ = CollisionSolver.resolve(particle: &p, surfaceY: 0, surfaceVelocity: .zero, restitution: 0, friction: 0.75, restSpeed: 35)
        XCTAssertEqual(p.velocity.x, 25, accuracy: 0.01)
    }

    func testMovingSurfaceDragsParticle() {
        var p = falling(vy: -100, vx: 0)
        _ = CollisionSolver.resolve(particle: &p, surfaceY: 0, surfaceVelocity: SIMD2(200, 0), restitution: 0, friction: 1, restSpeed: 35)
        XCTAssertEqual(p.velocity.x, 200, accuracy: 0.01)
    }

    func testCrossingDetectedInWorldAndDepositsSnow() {
        var c = SimulationConfiguration(); c.density = 0; c.windStrength = 0; c.turbulence = 0
        let w = PhysicsWorld(config: c)
        w.setSurfaces([CollisionSurface(id: "w", frame: CGRect(x: 0, y: 100, width: 400, height: 50), velocity: .zero, kind: .windowTop)])
        var s = SnowParticle.blank
        s.position = SIMD2(200, 150.5); s.velocity = SIMD2(0, -400); s.mass = 1; s.volume = 6
        w.pool.spawn(s)
        w.step(dt: 1.0 / 120)
        XCTAssertEqual(w.pool.count, 0, "particle should land")
        XCTAssertEqual(w.state(forSurface: "w")!.field.volume, 6, accuracy: 0.01)
    }

    func testParticleBelowSurfaceIsIgnored() {
        var c = SimulationConfiguration(); c.density = 0
        let w = PhysicsWorld(config: c)
        w.setSurfaces([CollisionSurface(id: "w", frame: CGRect(x: 0, y: 100, width: 400, height: 50), velocity: .zero, kind: .windowTop)])
        var s = SnowParticle.blank
        s.position = SIMD2(200, 120); s.velocity = SIMD2(0, -50); s.mass = 1
        w.pool.spawn(s)
        w.step(dt: 1.0 / 120)
        XCTAssertEqual(w.pool.count, 1)
    }

    func testSurfaceIndexBroadPhase() {
        var idx = SurfaceIndex()
        idx.rebuild(spans: [(0, 300), (1000, 1200)])
        XCTAssertEqual(idx.candidates(x: 100), [0])
        XCTAssertEqual(idx.candidates(x: 1100), [1])
        XCTAssertTrue(idx.candidates(x: 600).isEmpty)
        XCTAssertTrue(idx.candidates(x: -5000).isEmpty)
    }
}
