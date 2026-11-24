import Foundation

enum TargetFrameRate: String, Codable, CaseIterable, Identifiable, Sendable {
    case fps30
    case fps60
    case adaptive

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fps30: "30 FPS"
        case .fps60: "60 FPS"
        case .adaptive: "Adaptive"
        }
    }
}

/// User preferences. Pure value type; UI state and simulation state live elsewhere.
/// Ranges: `particleDensity` and `windStrength` are normalized 0...1.
struct SnowfallSettings: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int = SnowfallSettings.currentVersion
    var snowfallEnabled: Bool = true
    var particleDensity: Double = 0.5
    var windStrength: Double = 0.25
    var accumulationEnabled: Bool = true
    var pointerInteractionEnabled: Bool = true
    var windowPhysicsEnabled: Bool = false
    var targetFrameRate: TargetFrameRate = .fps60
    var lowPowerMode: Bool = false
    var launchAtLogin: Bool = false

    static let `default` = SnowfallSettings()

    /// Returns a copy with all values clamped into their valid ranges.
    func validated() -> SnowfallSettings {
        var s = self
        s.particleDensity = Self.clamp01(particleDensity)
        s.windStrength = Self.clamp01(windStrength)
        s.version = Self.currentVersion
        return s
    }

    private static func clamp01(_ v: Double) -> Double {
        v.isFinite ? min(max(v, 0), 1) : 0
    }
}
