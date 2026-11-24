import Foundation
import os

/// Runs the physics world on a dedicated serial queue with a fixed timestep, and publishes
/// immutable snapshots for renderers. All mutable state is confined to `queue`; the only shared
/// data is the lock-protected snapshot, so renderers never wait on physics.
final class SimulationCoordinator: @unchecked Sendable {
    private let queue = DispatchQueue(label: "snowfall.simulation", qos: .userInteractive)
    private let monitor: PerformanceMonitor
    private let snapshotLock = OSAllocatedUnfairLock(initialState: RenderSnapshot())

    // Queue-confined state.
    private var world: PhysicsWorld
    private var base: SimulationConfiguration
    private var settings = SimulationSettings()
    private var timer: DispatchSourceTimer?
    private var lastTick: UInt64 = 0
    private var accumulator: Double = 0
    private var back = RenderSnapshot()
    private var sequence: UInt64 = 0
    private var densityScale: Float = 1
    private var lastAdapt: UInt64 = 0
    private var surfaceBuilder = SurfaceBuilder()
    private var displays: [DisplayDescriptor] = []
    private var windows: [WindowSnapshot] = []
    private var didPrewarm = false
    private var pointerStamp: UInt64 = 0
    private var targetFPS: Double = 60
    private var lastStepMs: Double = 0

    init(monitor: PerformanceMonitor, base: SimulationConfiguration = SimulationConfiguration()) {
        self.monitor = monitor
        self.base = base
        self.world = PhysicsWorld(config: base)
        back.particles.reserveCapacity(base.poolCapacity)
        back.heights.reserveCapacity(64 * 1024)
    }

    // MARK: Inputs (any thread)

    func apply(settings s: SimulationSettings, targetFPS fps: Double) {
        queue.async { [self] in
            let previousFPS = targetFPS
            settings = s
            targetFPS = fps
            world.configure(s.configuration(base: base, densityScale: densityScale))
            rebuildSurfaces()
            if !s.running { stopTimer() }
            else if timer == nil || previousFPS != fps { startTimer() }
        }
    }

    func updateDisplays(_ d: [DisplayDescriptor]) {
        queue.async { [self] in
            displays = d
            rebuildRegion()
            rebuildSurfaces()
        }
    }

    func updateWindows(_ w: [WindowSnapshot]) {
        queue.async { [self] in
            windows = w
            rebuildSurfaces()
        }
    }

    func updatePointer(_ p: PointerSample?) {
        queue.async { [self] in
            guard let p else { world.pointer.isActive = false; return }
            world.pointer.position = SIMD2(p.x, p.y)
            world.pointer.velocity = SIMD2(p.vx, p.vy)
            world.pointer.isActive = settings.pointerEnabled
            world.pointer.radius = Float(settings.pointerRadius)
            world.pointer.strength = Float(500 + settings.pointerStrength * 4500)
            pointerStamp = DispatchTime.now().uptimeNanoseconds
        }
    }

    /// Sends the snow plow across the floor (no-op if it is already running).
    func sendPlow() { queue.async { [self] in world.startPlow() } }

    func clearSnow() { queue.async { [self] in world.clearSnow(); publish() } }

    /// Call after sleep/wake or any long suspension so elapsed time does not burst into physics.
    func resetClock() { queue.async { [self] in lastTick = DispatchTime.now().uptimeNanoseconds; accumulator = 0 } }

    func shutdown() { queue.async { [self] in stopTimer() } }

    func latestSnapshot() -> RenderSnapshot { snapshotLock.withLock { $0 } }

    // MARK: Queue-confined implementation

    private func rebuildRegion() {
        let r = displays.reduce(CGRect.null) { $0.union($1.frame) }
        world.setRegion(r.isNull ? .zero : r)
        if !didPrewarm, !r.isNull, settings.running { world.prewarm(); didPrewarm = true }
    }

    private func rebuildSurfaces() {
        var surfaces = displays.map(\.bottomSurface)
        if settings.windowPhysics {
            surfaces += surfaceBuilder.update(snapshots: windows, displays: displays)
        } else {
            _ = surfaceBuilder.update(snapshots: [], displays: displays)
        }
        world.setSurfaces(surfaces)
    }

    private func startTimer() {
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        let interval = 1.0 / max(15, targetFPS)
        t.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(2))
        t.setEventHandler { [weak self] in self?.tick() }
        lastTick = DispatchTime.now().uptimeNanoseconds
        accumulator = 0
        timer = t
        t.resume()
        if !didPrewarm { rebuildRegion() }
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        let now = DispatchTime.now().uptimeNanoseconds
        var elapsed = Double(now &- lastTick) / 1e9
        lastTick = now
        let cfg = world.config
        elapsed = min(max(elapsed, 0), cfg.maxElapsed)     // clamp suspension / stalls
        accumulator += elapsed
        let dt = Double(cfg.fixedTimestep)
        var steps = 0
        let t0 = DispatchTime.now().uptimeNanoseconds
        if world.pointer.isActive, now &- pointerStamp > 150_000_000 { world.pointer.velocity = .zero }
        while accumulator >= dt && steps < cfg.maxSubsteps {
            world.step(dt: cfg.fixedTimestep)
            accumulator -= dt
            steps += 1
        }
        if steps == cfg.maxSubsteps { accumulator = 0 }   // avoid spiral of death
        world.finishFrame()
        let ms = Double(DispatchTime.now().uptimeNanoseconds &- t0) / 1e6
        monitor.recordSimStep(ms: ms)
        lastStepMs = ms
        adaptIfNeeded(now: now)
        publish()
    }

    private func adaptIfNeeded(now: UInt64) {
        guard now &- lastAdapt > 1_000_000_000 else { return }
        lastAdapt = now
        let r = monitor.reading()
        let new = AdaptiveQuality.next(scale: densityScale, fps: r.renderFPS, targetFPS: targetFPS, simMs: r.simMs)
        if new != densityScale {
            densityScale = new
            world.configure(settings.configuration(base: base, densityScale: densityScale))
        }
    }

    private func publish() {
        var stats = SimulationStats()
        stats.simStepMs = lastStepMs
        stats.densityScale = densityScale
        world.fill(snapshot: &back, showSurfaces: settings.showSurfaces, stats: stats)
        sequence &+= 1
        back.sequence = sequence
        snapshotLock.withLock { front in swap(&front, &back) }
    }
}
