import Foundation
import simd

final class SurfaceState {
    var surface: CollisionSurface
    var field: SnowAccumulationField
    var dirty = false
    init(surface: CollisionSurface, field: SnowAccumulationField) {
        self.surface = surface
        self.field = field
    }
}

struct WorldTotals: Equatable {
    var clippedVolume: Float = 0
    var droppedVolume: Float = 0
}

/// Owns particles, surfaces and height fields. Single-threaded (simulation queue only).
/// `step(dt:)` performs no heap allocation: storage is fixed, loops use the pool's raw buffer.
final class PhysicsWorld {
    private(set) var config: SimulationConfiguration
    private(set) var pool: ParticlePool
    private(set) var time: Double = 0
    var pointer = PointerState()
    private(set) var region = CGRect.zero
    private(set) var totals = WorldTotals()

    private var rng: SeededRNG
    private var forceField: ForceField
    private var spawnAccumulator: Float = 0
    private var states: [String: SurfaceState] = [:]
    private var ordered: [SurfaceState] = []
    private var index = SurfaceIndex()

    init(config: SimulationConfiguration = SimulationConfiguration()) {
        self.config = config
        pool = ParticlePool(capacity: config.poolCapacity)
        rng = SeededRNG(seed: config.seed)
        forceField = ForceField(windStrength: config.windStrength, windMaxSpeed: config.windMaxSpeed,
                                turbulence: config.turbulence)
    }

    // MARK: Configuration

    func configure(_ new: SimulationConfiguration) {
        if new.poolCapacity != pool.capacity {
            let old = pool
            pool = ParticlePool(capacity: new.poolCapacity)
            for i in 0..<min(old.count, pool.capacity) { pool.spawn(old[i]) }
        }
        config = new
        forceField = ForceField(windStrength: new.windStrength, windMaxSpeed: new.windMaxSpeed,
                                turbulence: new.turbulence)
        for s in ordered {
            s.field.maxDepth = s.surface.kind == .displayBottom ? new.displayMaxDepth : new.windowMaxDepth
        }
    }

    func setRegion(_ r: CGRect) { region = r }

    var surfaceCount: Int { ordered.count }
    var surfaceStates: [SurfaceState] { ordered }
    func state(forSurface id: String) -> SurfaceState? { states[id] }
    var settledVolume: Float { ordered.reduce(0) { $0 + $1.field.volume } }

    // MARK: Surfaces

    /// Reconciles the surface set. New ids start empty; changed windows displace snow; removed
    /// windows release their snow as bounded falling clusters; removed displays drop their snow.
    func setSurfaces(_ incoming: [CollisionSurface]) {
        var seen = Set<String>()
        for s in incoming {
            seen.insert(s.id)
            if let st = states[s.id] {
                if st.surface.frame != s.frame { surfaceChanged(st, to: s) }
                st.surface = s
            } else {
                let depth = s.kind == .displayBottom ? config.displayMaxDepth : config.windowMaxDepth
                states[s.id] = SurfaceState(surface: s, field: SnowAccumulationField(width: Float(s.frame.width), maxDepth: depth))
            }
        }
        for (id, st) in states where !seen.contains(id) {
            if st.surface.kind == .windowTop {
                let clusters = SnowDisplacementSolver.release(field: st.field, frame: st.surface.frame,
                                                              maxClusters: config.maxDisplacementClusters)
                emit(clusters)
            }
            states[id] = nil
        }
        ordered = incoming.compactMap { states[$0.id] }
        index.rebuild(spans: ordered.map { ($0.surface.minX, $0.surface.maxX) })
    }

    private func surfaceChanged(_ st: SurfaceState, to new: CollisionSurface) {
        switch new.kind {
        case .displayBottom:
            if abs(Float(new.frame.width) - st.field.width) > 0.5 {
                let r = st.field.remapped(toWidth: Float(new.frame.width))
                st.field = r.field
                totals.clippedVolume += r.clipped
            }
        case .windowTop:
            let r = SnowDisplacementSolver.displace(field: st.field, oldFrame: st.surface.frame,
                                                    newFrame: new.frame, velocity: new.velocity,
                                                    stickSpeed: config.windowStickSpeed,
                                                    maxClusters: config.maxDisplacementClusters)
            st.field = r.field
            st.dirty = true
            totals.clippedVolume += r.clippedVolume
            emit(r.clusters)
        }
    }

    private func emit(_ clusters: [DisplacedCluster]) {
        for c in clusters {
            let radius = min(max(sqrt(c.volume / (Float.pi * config.compaction)) * 0.6, 2), 12)
            let p = SnowParticle(position: c.position, velocity: c.velocity, radius: radius, rotation: 0,
                                 angularVelocity: 0.5, opacity: 0.95, mass: 1.6, volume: c.volume,
                                 stateTime: 0, state: .displaced)
            if !pool.spawn(p) { totals.droppedVolume += c.volume }
        }
    }

    func clearSnow() {
        for s in ordered { s.field.clear() }
    }

    func clearParticles() { pool.removeAll() }

    // MARK: Stepping

    func step(dt: Float) {
        time += Double(dt)
        let t = Float(time)
        spawn(dt: dt)

        let cfg = config
        let g = SIMD2<Float>(0, -cfg.gravity * cfg.fallSpeedScale)
        let ptr = pool.base
        let useSurfaces = !ordered.isEmpty
        var i = 0
        while i < pool.count {
            var p = ptr[i]
            var a = g
            if pointer.isActive {
                let pa = ForceField.pointerAcceleration(particle: p.position, pointer: pointer)
                if pa != .zero { a += pa; p.state = .disturbed; p.stateTime = 0 }
            }
            let k = cfg.baseDrag / p.mass
            let wind = forceField.airVelocity(at: p.position, time: t)
            p.velocity = (p.velocity + (a + k * wind) * dt) / (1 + k * dt)
            let speed = simd_length(p.velocity)
            if speed > cfg.maxSpeed { p.velocity *= cfg.maxSpeed / speed }
            let prevY = p.position.y
            p.position += p.velocity * dt
            p.rotation += p.angularVelocity * dt
            if p.state == .disturbed {
                p.stateTime += dt
                if p.stateTime > 0.6 { p.state = .falling }
            }

            if !(p.position.x.isFinite && p.position.y.isFinite) || isOutside(p.position) {
                pool.remove(at: i); continue
            }
            if useSurfaces, collide(&p, prevY: prevY) {
                pool.remove(at: i); continue
            }
            ptr[i] = p
            i += 1
        }
    }

    /// Returns true when the particle came to rest (and should be removed).
    private func collide(_ p: inout SnowParticle, prevY: Float) -> Bool {
        let x = p.position.x
        let cand = index.candidates(x: x)
        if cand.isEmpty { return false }
        var best: SurfaceState?
        var bestY = -Float.infinity
        for ci in cand {
            let s = ordered[ci]
            let sf = s.surface
            guard x >= sf.minX, x <= sf.maxX, prevY >= sf.topY - 0.001 else { continue }
            let eff = sf.topY + (config.accumulationEnabled ? s.field.height(atLocalX: x - sf.minX) : 0)
            if p.position.y <= eff && eff > bestY { best = s; bestY = eff }
        }
        guard let s = best else { return false }
        let sv = SIMD2(Float(s.surface.velocity.dx), Float(s.surface.velocity.dy))
        let outcome = CollisionSolver.resolve(particle: &p, surfaceY: bestY, surfaceVelocity: sv,
                                              restitution: config.restitution, friction: config.friction,
                                              restSpeed: config.restSpeed)
        guard outcome == .rested else { return false }
        if config.accumulationEnabled {
            let depth = s.field.maxDepth
            let spread = min(64, max(3, Int(p.volume / max(0.5, depth * s.field.binWidth * 0.5)) + 3))
            s.field.deposit(localX: x - s.surface.minX, volume: p.volume, spreadBins: spread)
            s.dirty = true
        }
        return true
    }

    private func isOutside(_ p: SIMD2<Float>) -> Bool {
        guard !region.isEmpty else { return false }
        return p.y < Float(region.minY) - 60 || p.x < Float(region.minX) - 800 || p.x > Float(region.maxX) + 800
    }

    // MARK: Spawning

    var targetCount: Int {
        let area = Float(max(region.width * region.height, 1))
        let areaFactor = min(1, area / 2_000_000)
        return min(config.maxParticles, Int(Float(config.maxParticles) * config.density * config.densityScale * areaFactor))
    }

    private func spawn(dt: Float) {
        guard !region.isEmpty else { return }
        let target = targetCount
        guard pool.count < target else { spawnAccumulator = 0; return }
        spawnAccumulator += Float(target) / 12 * dt
        while spawnAccumulator >= 1 {
            spawnAccumulator -= 1
            guard pool.count < min(target, config.maxParticles) else { break }
            spawnOne(y: Float(region.maxY) + rng.float(4...40))
        }
    }

    func spawnOne(y: Float) {
        let u = rng.float(0...1)
        let r = config.minRadius + (config.maxRadius - config.minRadius) * pow(u, 2.2)
        let x = rng.float((Float(region.minX) - 300)...(Float(region.maxX) + 300))
        let mass = 0.8 + 0.5 * (r - config.minRadius) / max(config.maxRadius - config.minRadius, 0.1)
        let p = SnowParticle(position: SIMD2(x, y), velocity: SIMD2(0, -50), radius: r,
                             rotation: rng.float(0...6.28), angularVelocity: rng.float(-1.5...1.5),
                             opacity: rng.float(0.55...1) * config.opacityScale, mass: mass,
                             volume: config.compaction * Float.pi * r * r, stateTime: 0, state: .falling)
        pool.spawn(p)
    }

    /// Seeds particles across the region so snowfall looks established immediately.
    func prewarm() {
        guard !region.isEmpty else { return }
        let n = Int(Float(targetCount) * 0.7)
        for _ in 0..<n {
            spawnOne(y: rng.float(Float(region.minY)...Float(region.maxY)))
        }
    }

    // MARK: Per-frame maintenance

    /// Relaxes fields, clips depth, and sheds a bounded amount at window edges. Call once per frame.
    func finishFrame() {
        for s in ordered {
            guard s.dirty else { continue }
            let moved = s.field.relax(iterations: 3)
            totals.clippedVolume += s.field.clipToMaxDepth()
            if s.surface.kind == .windowTop {
                let flake = config.compaction * Float.pi * config.maxRadius * config.maxRadius
                let shed = s.field.shedEdges(edgeBins: 3, edgeLimit: s.field.maxDepth * 0.35,
                                             minVolume: flake, maxVolume: flake * 3)
                let f = s.surface.frame
                let y = Float(f.maxY) + 1
                if shed.left > 0 { emit([DisplacedCluster(position: SIMD2(Float(f.minX) - 1, y), velocity: SIMD2(-40, 0), volume: shed.left)]) }
                if shed.right > 0 { emit([DisplacedCluster(position: SIMD2(Float(f.maxX) + 1, y), velocity: SIMD2(40, 0), volume: shed.right)]) }
            }
            if !moved { s.dirty = false }
        }
    }

    /// x-spans where windows stacked *in front of* this window cover its top edge. Snow resting on
    /// a covered edge is not drawn (it reappears when the cover moves or closes); new snow lands on
    /// the front window instead because collision picks the highest surface.
    func occludedSpans(for st: SurfaceState) -> [(Float, Float)] {
        guard st.surface.kind == .windowTop else { return [] }
        let top = CGFloat(st.surface.topY)
        return ordered.compactMap { o in
            guard o !== st, o.surface.kind == .windowTop, o.surface.zRank < st.surface.zRank,
                  o.surface.frame.minY < top, o.surface.frame.maxY > top else { return nil }
            return (o.surface.minX, o.surface.maxX)
        }
    }

    func fill(snapshot s: inout RenderSnapshot, showSurfaces: Bool, stats: SimulationStats) {
        s.particles.removeAll(keepingCapacity: true)
        s.surfaces.removeAll(keepingCapacity: true)
        s.heights.removeAll(keepingCapacity: true)
        s.debugRects.removeAll(keepingCapacity: true)
        let n = pool.count
        for i in 0..<n {
            let p = pool[i]
            s.particles.append(RenderParticle(position: p.position, radius: p.radius, rotation: p.rotation,
                                              opacity: p.opacity, seed: Float(i & 255) / 255))
        }
        for st in ordered {
            let sf = st.surface
            if config.accumulationEnabled, !st.field.isEmpty {
                s.surfaces.append(RenderSurface(minX: sf.minX, baseY: sf.topY, binWidth: st.field.binWidth,
                                                binCount: st.field.binCount, heightOffset: s.heights.count,
                                                maxDepth: st.field.maxDepth))
                let hidden = occludedSpans(for: st)
                for b in 0..<st.field.binCount {
                    let cx = sf.minX + (Float(b) + 0.5) * st.field.binWidth
                    let isHidden = hidden.contains { cx >= $0.0 && cx <= $0.1 }
                    s.heights.append(isHidden ? 0 : st.field.height(atBin: b))
                }
            }
            if showSurfaces {
                let c: SIMD4<Float> = sf.kind == .windowTop ? SIMD4(1, 0.3, 0.2, 0.9) : SIMD4(0.2, 0.7, 1, 0.9)
                s.debugRects.append(DebugRect(rect: SIMD4(sf.minX, sf.topY - 1, Float(sf.frame.width), 2), color: c))
            }
        }
        var st = stats
        st.particleCount = n
        st.surfaceCount = ordered.count
        st.windowSurfaceCount = ordered.filter { $0.surface.kind == .windowTop }.count
        st.settledVolume = settledVolume
        st.clippedVolume = totals.clippedVolume
        st.droppedVolume = totals.droppedVolume
        s.stats = st
    }
}
