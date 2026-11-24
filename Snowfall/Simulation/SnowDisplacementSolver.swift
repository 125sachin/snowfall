import Foundation
import simd

struct DisplacedCluster: Sendable, Equatable {
    var position: SIMD2<Float>   // global points
    var velocity: SIMD2<Float>
    var volume: Float            // pt²
}

struct DisplacementResult {
    var field: SnowAccumulationField
    var clusters: [DisplacedCluster]
    var retainedVolume: Float
    var displacedVolume: Float
    var clippedVolume: Float
}

/// Converts window frame changes into snow motion. Event-time only (not in the per-step path).
///
/// Policy (documented in docs/IMPLEMENTATION_PLAN.md):
/// - Below `stickSpeed` the pile is carried with the window.
/// - Between `stickSpeed` and `2·stickSpeed` an increasing fraction `f` slips: horizontally the
///   pile lags by `dx·f`; any part that leaves the new top edge, plus `f` of the whole pile on
///   a vertical move, becomes falling clusters (bounded by `maxClusters`).
/// - Volume is conserved: retained + displaced + clipped == old volume (to float tolerance).
enum SnowDisplacementSolver {
    static func displace(field: SnowAccumulationField, oldFrame: CGRect, newFrame: CGRect,
                         velocity: CGVector, stickSpeed: Float, maxClusters: Int) -> DisplacementResult {
        let speed = Float(hypot(velocity.dx, velocity.dy))
        let stick = max(stickSpeed, 1)
        let f = min(max((speed - stick) / stick, 0), 1)
        let dx = Float(newFrame.minX - oldFrame.minX)
        let dy = Float(newFrame.maxY - oldFrame.maxY)
        let slip = dx * f
        let fv: Float = abs(dy) > 0.5 ? f : 0

        var out = SnowAccumulationField(width: Float(newFrame.width), maxDepth: field.maxDepth)
        var shed = [Float](repeating: 0, count: field.binCount)
        let bw = field.binWidth
        for i in 0..<field.binCount {
            let vol = field.height(atBin: i) * bw
            guard vol > 0 else { continue }
            let carried = vol * (1 - fv)
            shed[i] += vol * fv
            let a = Float(i) * bw - slip, b = a + bw
            let lo = max(a, 0), hi = min(b, out.width)
            if hi > lo {
                let inside = carried * (hi - lo) / bw
                shed[i] += carried - inside
                out.spread(volume: inside, from: lo, to: hi)
            } else {
                shed[i] += carried
            }
        }
        let clipped = out.clipToMaxDepth()
        let clusters = makeClusters(shed: shed, field: field, frame: oldFrame, velocity: velocity,
                                    maxClusters: maxClusters)
        let displaced = clusters.reduce(0) { $0 + $1.volume }
        return DisplacementResult(field: out, clusters: clusters, retainedVolume: out.volume,
                                  displacedVolume: displaced, clippedVolume: clipped)
    }

    /// Releases the whole pile as bounded falling clusters (window closed / disappeared).
    static func release(field: SnowAccumulationField, frame: CGRect, maxClusters: Int) -> [DisplacedCluster] {
        let shed = (0..<field.binCount).map { field.height(atBin: $0) * field.binWidth }
        return makeClusters(shed: shed, field: field, frame: frame, velocity: .zero, maxClusters: maxClusters)
    }

    private static func makeClusters(shed: [Float], field: SnowAccumulationField, frame: CGRect,
                                     velocity: CGVector, maxClusters: Int) -> [DisplacedCluster] {
        let n = field.binCount
        let group = max(1, Int((Float(n) / Float(max(1, maxClusters))).rounded(.up)))
        let v = SIMD2(Float(velocity.dx), Float(velocity.dy)) * 0.5
        let vc = SIMD2(min(max(v.x, -600), 600), min(max(v.y, -600), 600))
        var result: [DisplacedCluster] = []
        var g = 0
        while g < n {
            let end = min(n, g + group)
            var vol: Float = 0, wx: Float = 0, wy: Float = 0
            for i in g..<end where shed[i] > 0 {
                vol += shed[i]
                wx += shed[i] * (Float(frame.minX) + (Float(i) + 0.5) * field.binWidth)
                wy += shed[i] * (Float(frame.maxY) + field.height(atBin: i))
            }
            if vol > 1e-3 {
                result.append(DisplacedCluster(position: SIMD2(wx / vol, wy / vol), velocity: vc, volume: vol))
            }
            g = end
        }
        return result
    }
}
