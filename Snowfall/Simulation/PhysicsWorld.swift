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
    /// Volume that left the system: plow dumped off the end of the floor, or despawned in flight.
    var lostVolume: Float = 0
}

/// A snow-plow vehicle (JCB) driving right → left along the display floor.
struct PlowVehicle {
    static let spriteScale: Float = 0.9
    static let spriteWidth: Float = 180 * spriteScale
    static let wheelRadius: Float = 30 * spriteScale

    var bladeX: Float
    var groundY: Float
    var speed: Float = 30
    var carried: Float = 0          // pt² of snow currently pushed ahead of the blade
    var wheelAngle: Float = 0
    var sprayAccumulator: Float = 0
    var pileHeight: Float { min(46, sqrt(max(carried, 0)) * 0.9) }
}

/// Owns particles, surfaces and height fields. Single-threaded (simulation queue only).
/// `step(dt:)` performs no heap allocation: storage is fixed, loops use the pool's raw buffer.
final class PhysicsWorld {
    private(set) var config: SimulationConfiguration
    private(set) var pool: ParticlePool
    private(set) var time: Double = 0
    var pointer = PointerState()
    private(set) var region = CGRect.zero
    var totals = WorldTotals()

    var rng: SeededRNG
    private var forceField: ForceField
    private var spawnAccumulator: Float = 0
    private var states: [String: SurfaceState] = [:]
    var ordered: [SurfaceState] = []
    private var index = SurfaceIndex()
    private(set) var plow: PlowVehicle?
    var santa: SantaRun?
    var tornado: Tornado?
    var lastHelperEnd: Double = 0
    private var plowBlockedState: SurfaceState?
    private var plowBlockedEdge: Int?

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

    func emit(_ clusters: [DisplacedCluster]) {
        for c in clusters {
            let radius = min(max(sqrt(c.volume / (Float.pi * config.compaction)) * 0.6, 2), 12)
            let p = SnowParticle(position: c.position, velocity: c.velocity, radius: radius, rotation: 0,
                                 angularVelocity: 0.5, opacity: 0.95, mass: 1.6, volume: c.volume,
                                 stateTime: 0, state: .displaced)
            if !pool.spawn(p) { totals.droppedVolume += c.volume }
        }
    }

    var isPlowRunning: Bool { plow != nil }
    var isHelperRunning: Bool { plow != nil || santa != nil || tornado != nil }

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
            if p.state == .swirling || p.state == .sparkle {
                let keep = p.state == .swirling ? stepSwirl(&p, dt: dt) : stepSparkle(&p, dt: dt)
                if keep { ptr[i] = p; i += 1 } else { pool.remove(at: i) }
                continue
            }
            var a = g
            if let tw = tornado, tw.strength > 0.05, p.orbitRadius >= 0 {
                a += tornadoInfluence(&p, tornado: tw)
                if p.state == .swirling { ptr[i] = p; i += 1; continue }     // taken into the funnel
            }
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
                if p.volume.isFinite { totals.lostVolume += p.volume }
                pool.remove(at: i); continue
            }
            if useSurfaces, collide(&p, prevY: prevY) {
                pool.remove(at: i); continue
            }
            ptr[i] = p
            i += 1
        }
        stepPlow(dt: dt)
        stepSanta(dt: dt)
        stepTornado(dt: dt)
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
            let spread = min(64, max(3, Int(p.volume / max(0.5, depth * s.field.binWidth * 0.3)) + 3))
            var localX = x - s.surface.minX
            // Snow the blade spilled must stay ahead of it: if it would land within the blade's
            // reach, it settles just ahead of the blade (it is carried by the pile front).
            if p.state == .displaced, p.volume > 0, s === plowBlockedState, let edge = plowBlockedEdge {
                let half = max(1, spread / 2)
                let c = s.field.binIndex(atLocalX: localX)
                if c > edge - half && c <= edge + 20 {
                    localX = (Float(max(edge - half, 0)) + 0.5) * s.field.binWidth
                }
            }
            s.field.deposit(localX: localX, volume: p.volume, spreadBins: spread)
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
        let r = config.minRadius + (config.maxRadius - config.minRadius) * pow(u, 1.6)
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

    // MARK: Snow plow

    func floorState(at x: Float) -> SurfaceState? {
        for st in ordered where st.surface.kind == .displayBottom && x >= st.surface.minX && x <= st.surface.maxX {
            return st
        }
        return nil
    }

    private func volume(_ kind: HelperKind) -> Float {
        switch kind {
        case .jcb: return ordered.filter { $0.surface.kind == .displayBottom }.reduce(0) { max($0, $1.field.volume) }
        default: return ordered.reduce(0) { max($0, $1.field.volume) }
        }
    }

    /// Helpers that currently have enough snow to be worth running.
    func eligibleHelpers(minVolume: Float = 600) -> [HelperKind] {
        HelperKind.concrete.filter { volume($0) > minVolume }
    }

    /// Starts a helper now. `nil` uses the configured one; `.random` picks any concrete helper.
    func startHelper(_ kind: HelperKind? = nil) {
        guard !isHelperRunning, !region.isEmpty else { return }
        var k = kind ?? config.helper
        if k == .random { k = HelperKind.concrete[Int(rng.next() % UInt64(HelperKind.concrete.count))] }
        switch k {
        case .jcb: startPlow()
        case .santa: startSanta()
        case .random: break
        }
    }

    /// Sends the plow in from the right edge. No-op if one is already running.
    func startPlow() {
        guard plow == nil, santa == nil, !region.isEmpty else { return }
        let x = Float(region.maxX) + 20
        let ground = floorState(at: Float(region.maxX) - 1)?.surface.topY ?? Float(region.minY)
        plow = PlowVehicle(bladeX: x, groundY: ground)
    }

    private func emitPlowSnow(volume: Float, at p: SIMD2<Float>, velocity: SIMD2<Float>) {
        guard volume > 0 else { return }
        emit([DisplacedCluster(position: p, velocity: velocity, volume: volume)])
    }

    /// Plow dynamics: engine force − drag − load resistance (∝ pushed snow) drives speed; the blade
    /// sweeps the floor's height field, the removed snow becomes the carried pile, excess spills
    /// forward over the blade, and what remains is dumped off the end of the floor.
    private func stepPlow(dt: Float) {
        guard var p = plow else { return }
        let c = config
        let load = min(p.carried, 2 * c.plowCapacity) * c.plowLoadResistance
        let accel = c.plowEngineForce - load - c.plowDrag * p.speed
        p.speed = min(max(p.speed + accel * dt, c.plowMinSpeed), c.plowEngineForce / c.plowDrag)
        let oldX = p.bladeX
        let newX = oldX - p.speed * dt
        p.wheelAngle += p.speed * dt / PlowVehicle.wheelRadius

        plowBlockedState = nil; plowBlockedEdge = nil
        if let st = floorState(at: oldX) {
            p.groundY = st.surface.topY
            let a = newX - st.surface.minX, b = oldX - st.surface.minX
            let removed = st.field.sweep(fromLocalX: a, toLocalX: b, keepDepth: c.plowResidueDepth)
            p.carried += removed
            st.dirty = true
            plowBlockedState = st
            plowBlockedEdge = max(0, Int(ceil((newX - st.surface.minX) / st.field.binWidth - 0.5)) - 1)   // last unswept bin
            // Spray thrown by the blade (visual only: zero volume).
            p.sprayAccumulator += removed / 40
            var sprays = 0
            while p.sprayAccumulator >= 1, sprays < 3 {
                p.sprayAccumulator -= 1; sprays += 1
                var sp = SnowParticle.blank
                sp.position = SIMD2(newX - 2, p.groundY + rng.float(2...(4 + p.pileHeight)))
                sp.velocity = SIMD2(-p.speed * rng.float(0.4...1.1), rng.float(50...140))
                sp.radius = rng.float(1.2...2.6); sp.mass = 0.9; sp.opacity = 0.85; sp.volume = 0
                sp.state = .displaced
                pool.spawn(sp)
            }
        } else if p.carried > 0 {
            // Past the end of the floor: dump the pile; it falls away and is accounted as lost.
            var left = p.carried
            while left > 0 {
                let v = min(left, 250)
                left -= v
                totals.lostVolume += v
                var sp = SnowParticle.blank
                sp.position = SIMD2(oldX - rng.float(0...10), p.groundY + p.pileHeight * rng.float(0.3...1))
                sp.velocity = SIMD2(-p.speed * 0.5, rng.float(0...40))
                sp.radius = min(10, 2 + sqrt(v) * 0.25); sp.mass = 1.6; sp.opacity = 0.95; sp.volume = 0
                sp.state = .displaced
                pool.spawn(sp)
            }
            p.carried = 0
        }

        // Overflow: snow that does not fit on the blade spills over the pile, ahead of the vehicle.
        if p.carried > c.plowCapacity {
            let v = min(p.carried - c.plowCapacity, 160)
            p.carried -= v
            emitPlowSnow(volume: v,
                         at: SIMD2(newX - 3, p.groundY + p.pileHeight + 2),
                         velocity: SIMD2(-p.speed * rng.float(1.4...1.8) - rng.float(30...60), rng.float(25...70)))   // faster than the blade, so it lands ahead
        }

        p.bladeX = newX
        if newX < Float(region.minX) - PlowVehicle.spriteWidth - 20 {
            plow = nil
            lastHelperEnd = time
            plowBlockedState = nil; plowBlockedEdge = nil
        } else {
            plow = p
        }
    }

    // MARK: Per-frame maintenance

    /// Relaxes fields, clips depth, and sheds a bounded amount at window edges. Call once per frame.
    func finishFrame() {
        if config.plowAuto, !isHelperRunning, time - lastHelperEnd >= Double(config.plowInterval) {
            let ok = eligibleHelpers()
            if config.helper == .random, let pick = ok.isEmpty ? nil : ok[Int(rng.next() % UInt64(ok.count))] {
                startHelper(pick)
            } else if config.helper != .random, ok.contains(config.helper) {
                startHelper(config.helper)
            }
        }
        for s in ordered {
            guard s.dirty else { continue }
            let moved = s.field.relax(iterations: 3, blockedEdge: s === plowBlockedState ? plowBlockedEdge : nil)
            let clipped = s.field.clipToMaxDepth()
            if clipped > 0, s === plowBlockedState, plow != nil {
                plow!.carried += clipped          // a pile too deep ahead of the blade is pushed along with it
            } else {
                totals.clippedVolume += clipped
            }
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

    private static func hash(_ x: Float) -> Float {
        let v = sin(x * 127.1) * 43758.5453
        return v - floor(v)
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
        s.vehicles.removeAll(keepingCapacity: true)
        s.santas.removeAll(keepingCapacity: true)
        if let sa = santa {
            s.santas.append(RenderSanta(x: sa.x, y: sa.y, bob: sin(sa.totalTime * 2.2) * 5, wandAngle: sa.wandAngle))
        }
        if let p = plow {
            s.vehicles.append(RenderVehicle(bladeX: p.bladeX, groundY: p.groundY,
                                            wheelAngle: p.wheelAngle, bob: sin(p.wheelAngle * 3) * 0.5))
            // Pushed pile in front of the blade (render-only flakes in a mound shape).
            let n = min(70, Int(p.carried / 22))
            let h = p.pileHeight, w = h * 1.7
            for k in 0..<n {
                let u = Self.hash(Float(k) * 1.37), v = Self.hash(Float(k) * 7.91 + 3)
                let x = p.bladeX + 3 - u * w
                let y = p.groundY + 2 + v * h * (1 - u * 0.85)
                s.particles.append(RenderParticle(position: SIMD2(x, y), radius: 2.5 + 3.5 * Self.hash(Float(k) * 3.3),
                                                  rotation: 0, opacity: 0.97, seed: Self.hash(Float(k))))
            }
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
