import Foundation

/// 1-D height field of settled snow along a horizontal surface.
/// Units: pt. `heights[i]` is the depth of bin `i`; volume (area, pt²) = depth · binWidth.
/// Storage is bounded: at most `maxBins` bins regardless of surface width.
struct SnowAccumulationField: Sendable, Equatable {
    static let maxBins = 1024
    static let targetBinWidth: Float = 4

    let width: Float
    let binCount: Int
    let binWidth: Float
    private(set) var heights: [Float]
    var maxDepth: Float
    /// Maximum depth difference between neighbours, as a multiple of bin width (angle of repose).
    var reposeSlope: Float = 0.7

    static func binCount(forWidth w: Float) -> Int {
        min(maxBins, max(4, Int((w / targetBinWidth).rounded(.up))))
    }

    init(width: Float, maxDepth: Float) {
        self.width = max(1, width)
        self.binCount = Self.binCount(forWidth: self.width)
        self.binWidth = self.width / Float(binCount)
        self.heights = Array(repeating: 0, count: binCount)
        self.maxDepth = maxDepth
    }

    var volume: Float { heights.reduce(0, +) * binWidth }
    var isEmpty: Bool { !heights.contains { $0 > 0.0001 } }

    func height(atBin i: Int) -> Float { heights[min(max(i, 0), binCount - 1)] }

    /// Linearly interpolated depth at a surface-local x.
    func height(atLocalX x: Float) -> Float {
        let f = x / binWidth - 0.5
        let i = Int(floor(f))
        let t = f - Float(i)
        return height(atBin: i) * (1 - t) + height(atBin: i + 1) * t
    }

    /// Deposits `volume` around `localX`, spread over ~`spreadBins` bins with triangular weights.
    /// Conserves volume (weights are renormalised over bins that exist).
    mutating func deposit(localX: Float, volume: Float, spreadBins: Int = 3) {
        guard volume > 0, volume.isFinite else { return }
        let c = min(max(Int(localX / binWidth), 0), binCount - 1)
        let h = max(1, spreadBins / 2)
        var total: Float = 0
        for k in -h...h {
            let i = c + k
            if i >= 0 && i < binCount { total += Float(h + 1 - abs(k)) }
        }
        guard total > 0 else { return }
        for k in -h...h {
            let i = c + k
            if i >= 0 && i < binCount {
                heights[i] += volume * (Float(h + 1 - abs(k)) / total) / binWidth
            }
        }
    }

    /// Adds volume directly to one bin (used by remapping).
    mutating func add(volume: Float, toBin i: Int) {
        guard i >= 0, i < binCount, volume > 0 else { return }
        heights[i] += volume / binWidth
    }

    /// One conservative relaxation pass toward the angle of repose. Returns true if anything moved.
    @discardableResult
    mutating func relax(iterations: Int = 2) -> Bool {
        var moved = false
        let limit = reposeSlope * binWidth
        for _ in 0..<iterations {
            var any = false
            for i in 0..<(binCount - 1) {
                let d = heights[i] - heights[i + 1]
                if abs(d) > limit {
                    let m = (abs(d) - limit) * 0.25
                    if d > 0 { heights[i] -= m; heights[i + 1] += m } else { heights[i] += m; heights[i + 1] -= m }
                    any = true
                }
            }
            moved = moved || any
            if !any { break }
        }
        return moved
    }

    /// Clips depth above `maxDepth`; returns the clipped volume (it leaves the system).
    @discardableResult
    mutating func clipToMaxDepth() -> Float {
        var clipped: Float = 0
        for i in 0..<binCount where heights[i] > maxDepth {
            clipped += (heights[i] - maxDepth) * binWidth
            heights[i] = maxDepth
        }
        return clipped
    }

    /// Sheds snow above a tapered limit at the first/last `edgeBins` bins. Nothing is removed
    /// unless the total excess reaches `minVolume`, and at most `maxVolume` leaves per call.
    /// Returns (left, right) shed volume.
    mutating func shedEdges(edgeBins: Int, edgeLimit: Float, minVolume: Float, maxVolume: Float) -> (left: Float, right: Float) {
        let nb = min(edgeBins, binCount / 2)
        guard nb > 0 else { return (0, 0) }
        func limit(_ k: Int) -> Float { edgeLimit * Float(k + 1) / Float(nb + 1) }
        var leftExcess: Float = 0, rightExcess: Float = 0
        for k in 0..<nb {
            leftExcess += max(0, heights[k] - limit(k)) * binWidth
            rightExcess += max(0, heights[binCount - 1 - k] - limit(k)) * binWidth
        }
        var left: Float = 0, right: Float = 0
        if leftExcess >= minVolume {
            var budget = min(leftExcess, maxVolume)
            for k in 0..<nb where budget > 0 {
                let take = min(max(0, heights[k] - limit(k)) * binWidth, budget)
                heights[k] -= take / binWidth; budget -= take; left += take
            }
        }
        if rightExcess >= minVolume {
            var budget = min(rightExcess, maxVolume)
            for k in 0..<nb where budget > 0 {
                let i = binCount - 1 - k
                let take = min(max(0, heights[i] - limit(k)) * binWidth, budget)
                heights[i] -= take / binWidth; budget -= take; right += take
            }
        }
        return (left, right)
    }

    mutating func clear() {
        for i in 0..<binCount { heights[i] = 0 }
    }

    /// Redistributes snow proportionally onto a surface of a different width. Conserves volume
    /// (before clipping). Used when a display's resolution changes.
    func remapped(toWidth newWidth: Float) -> (field: SnowAccumulationField, clipped: Float) {
        var out = SnowAccumulationField(width: newWidth, maxDepth: maxDepth)
        let scale = out.width / width
        for i in 0..<binCount where heights[i] > 0 {
            let a = Float(i) * binWidth * scale, b = Float(i + 1) * binWidth * scale
            out.spread(volume: heights[i] * binWidth, from: a, to: b)
        }
        let clipped = out.clipToMaxDepth()
        return (out, clipped)
    }

    /// Distributes `volume` uniformly over the local interval [a, b] ∩ [0, width].
    mutating func spread(volume: Float, from a: Float, to b: Float) {
        let lo = max(a, 0), hi = min(b, width)
        guard hi > lo, volume > 0 else { return }
        let first = min(max(Int(lo / binWidth), 0), binCount - 1)
        let last = min(max(Int((hi - 1e-4) / binWidth), 0), binCount - 1)
        for j in first...last {
            let o = min(hi, Float(j + 1) * binWidth) - max(lo, Float(j) * binWidth)
            if o > 0 { add(volume: volume * o / (hi - lo), toBin: j) }
        }
    }
}
