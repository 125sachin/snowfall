import Foundation

enum TargetFrameRate: String, Codable, CaseIterable, Identifiable, Sendable {
    case fps30, fps60, adaptive
    var id: String { rawValue }
    var label: String {
        switch self {
        case .fps30: "30 FPS"
        case .fps60: "60 FPS"
        case .adaptive: "Adaptive"
        }
    }
}

/// User preferences. Pure value type. Normalised values are 0...1 unless noted.
/// Decoding tolerates missing keys (older versions) by falling back to defaults.
struct SnowfallSettings: Codable, Equatable, Sendable {
    static let currentVersion = 2

    var version = SnowfallSettings.currentVersion
    var snowfallEnabled = true
    var particleDensity = 0.5
    var windStrength = 0.25
    var fallSpeed = 1.0                 // 0.5...1.5 multiplier
    var particleOpacity = 1.0           // 0.3...1
    var maxParticles = 2000             // 200...3000
    var accumulationEnabled = true
    var maxAccumulationDepth = 0.5
    var pointerInteractionEnabled = true
    var pointerRadius = 120.0           // pt, 40...300
    var pointerStrength = 0.5
    var windowPhysicsEnabled = false
    var windowDisplacementStrength = 0.5
    var targetFrameRate = TargetFrameRate.fps60
    var lowPowerMode = false
    var launchAtLogin = false
    var showDiagnostics = false
    var showSurfaceDebug = false
    var plowAutomatic = true
    var plowIntervalMinutes = 3         // 1...60
    /// UUIDs of displays where snowfall is turned off.
    var disabledDisplays: [String] = []

    static let `default` = SnowfallSettings()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SnowfallSettings()
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? d.version
        snowfallEnabled = try c.decodeIfPresent(Bool.self, forKey: .snowfallEnabled) ?? d.snowfallEnabled
        particleDensity = try c.decodeIfPresent(Double.self, forKey: .particleDensity) ?? d.particleDensity
        windStrength = try c.decodeIfPresent(Double.self, forKey: .windStrength) ?? d.windStrength
        fallSpeed = try c.decodeIfPresent(Double.self, forKey: .fallSpeed) ?? d.fallSpeed
        particleOpacity = try c.decodeIfPresent(Double.self, forKey: .particleOpacity) ?? d.particleOpacity
        maxParticles = try c.decodeIfPresent(Int.self, forKey: .maxParticles) ?? d.maxParticles
        accumulationEnabled = try c.decodeIfPresent(Bool.self, forKey: .accumulationEnabled) ?? d.accumulationEnabled
        maxAccumulationDepth = try c.decodeIfPresent(Double.self, forKey: .maxAccumulationDepth) ?? d.maxAccumulationDepth
        pointerInteractionEnabled = try c.decodeIfPresent(Bool.self, forKey: .pointerInteractionEnabled) ?? d.pointerInteractionEnabled
        pointerRadius = try c.decodeIfPresent(Double.self, forKey: .pointerRadius) ?? d.pointerRadius
        pointerStrength = try c.decodeIfPresent(Double.self, forKey: .pointerStrength) ?? d.pointerStrength
        windowPhysicsEnabled = try c.decodeIfPresent(Bool.self, forKey: .windowPhysicsEnabled) ?? d.windowPhysicsEnabled
        windowDisplacementStrength = try c.decodeIfPresent(Double.self, forKey: .windowDisplacementStrength) ?? d.windowDisplacementStrength
        targetFrameRate = try c.decodeIfPresent(TargetFrameRate.self, forKey: .targetFrameRate) ?? d.targetFrameRate
        lowPowerMode = try c.decodeIfPresent(Bool.self, forKey: .lowPowerMode) ?? d.lowPowerMode
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        showDiagnostics = try c.decodeIfPresent(Bool.self, forKey: .showDiagnostics) ?? d.showDiagnostics
        showSurfaceDebug = try c.decodeIfPresent(Bool.self, forKey: .showSurfaceDebug) ?? d.showSurfaceDebug
        plowAutomatic = try c.decodeIfPresent(Bool.self, forKey: .plowAutomatic) ?? d.plowAutomatic
        plowIntervalMinutes = try c.decodeIfPresent(Int.self, forKey: .plowIntervalMinutes) ?? d.plowIntervalMinutes
        disabledDisplays = try c.decodeIfPresent([String].self, forKey: .disabledDisplays) ?? d.disabledDisplays
    }

    /// Returns a copy with every value clamped into its valid range.
    func validated() -> SnowfallSettings {
        var s = self
        s.particleDensity = Self.clamp(particleDensity, 0, 1)
        s.windStrength = Self.clamp(windStrength, 0, 1)
        s.fallSpeed = Self.clamp(fallSpeed, 0.5, 1.5, fallback: 1)
        s.particleOpacity = Self.clamp(particleOpacity, 0.3, 1, fallback: 1)
        s.maxParticles = min(max(maxParticles, 200), 3000)
        s.maxAccumulationDepth = Self.clamp(maxAccumulationDepth, 0, 1)
        s.pointerRadius = Self.clamp(pointerRadius, 40, 300, fallback: 120)
        s.pointerStrength = Self.clamp(pointerStrength, 0, 1)
        s.windowDisplacementStrength = Self.clamp(windowDisplacementStrength, 0, 1)
        s.plowIntervalMinutes = min(max(plowIntervalMinutes, 1), 60)
        s.disabledDisplays = Array(Set(disabledDisplays)).sorted()
        s.version = Self.currentVersion
        return s
    }

    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double, fallback: Double? = nil) -> Double {
        guard v.isFinite else { return fallback ?? lo }
        return min(max(v, lo), hi)
    }
}
