import Foundation
import os
import Darwin

struct PerformanceReading: Sendable, Equatable {
    var renderFPS: Double = 0
    var renderMs: Double = 0
    var simMs: Double = 0
    var memoryMB: Double = 0
    var cpuPercent: Double = 0
}

/// Thread-safe rolling performance counters.
final class PerformanceMonitor: @unchecked Sendable {
    private struct State {
        var lastFrame: CFTimeInterval = 0
        var fpsEMA: Double = 0
        var renderMsEMA: Double = 0
        var simMsEMA: Double = 0
        var lastCPU: Double = 0
        var lastWall: CFTimeInterval = 0
        var cpuPercent: Double = 0
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Called once per rendered frame (any overlay). `cpuMs` is the CPU encode time.
    func recordRenderFrame(cpuMs: Double) {
        let now = CACurrentMediaTimeShim.now()
        state.withLock { s in
            if s.lastFrame > 0 {
                let dt = now - s.lastFrame
                // Multiple overlays render per tick; the EMA over inter-frame gaps is per-overlay
                // only when one display is active. Documented in docs/TESTING.md.
                if dt > 0.0005 && dt < 1 { s.fpsEMA = s.fpsEMA == 0 ? 1 / dt : s.fpsEMA * 0.9 + (1 / dt) * 0.1 }
            }
            s.lastFrame = now
            s.renderMsEMA = s.renderMsEMA * 0.9 + cpuMs * 0.1
        }
    }

    func recordSimStep(ms: Double) {
        state.withLock { $0.simMsEMA = $0.simMsEMA * 0.95 + ms * 0.05 }
    }

    func resetFrameClock() {
        state.withLock { $0.lastFrame = 0; $0.fpsEMA = 0 }
    }

    func reading() -> PerformanceReading {
        let now = CACurrentMediaTimeShim.now()
        let cpu = Self.processCPUSeconds()
        let mem = Self.footprintMB()
        return state.withLock { s in
            if s.lastWall > 0, now - s.lastWall >= 1 {
                s.cpuPercent = (cpu - s.lastCPU) / (now - s.lastWall) * 100
                s.lastCPU = cpu; s.lastWall = now
            } else if s.lastWall == 0 { s.lastCPU = cpu; s.lastWall = now }
            let stale = now - s.lastFrame > 1
            return PerformanceReading(renderFPS: stale ? 0 : s.fpsEMA, renderMs: s.renderMsEMA,
                                      simMs: s.simMsEMA, memoryMB: mem, cpuPercent: s.cpuPercent)
        }
    }

    static func processCPUSeconds() -> Double {
        var u = rusage()
        getrusage(RUSAGE_SELF, &u)
        func sec(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1e6 }
        return sec(u.ru_utime) + sec(u.ru_stime)
    }

    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }
}

enum CACurrentMediaTimeShim {
    static func now() -> CFTimeInterval { ProcessInfo.processInfo.systemUptime }
}
