import Foundation

/// Snow helpers: characters/machines that periodically clear settled snow.
///
/// To add a helper:
/// 1. add a case here (and to `concrete`) with a label and summary;
/// 2. add its run state + `startX`/`stepX` to `PhysicsWorld` (see PlowVehicle, SantaRun) and call
///    them from `startHelper`, `step`, `eligible(_:)` and `isHelperRunning`;
/// 3. add a render type to `RenderSnapshot`, its sprites, and a draw call in `MetalRenderer`;
/// 4. add tests. The menu and Settings pickers pick the new case up automatically.
enum HelperKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case jcb
    case santa
    case random

    var id: String { rawValue }

    /// Helpers that can actually run. `.random` chooses one of these.
    static let concrete: [HelperKind] = [.jcb, .santa]

    var label: String {
        switch self {
        case .jcb: "JCB snow plow"
        case .santa: "Santa's magic tornado"
        case .random: "Surprise me"
        }
    }

    var shortLabel: String {
        switch self {
        case .jcb: "JCB"
        case .santa: "Santa"
        case .random: "Helper"
        }
    }

    var summary: String {
        switch self {
        case .jcb:
            "A JCB drives right to left along the bottom of the screen, pushing settled snow ahead of its blade. It slows under a heavy load, spills what doesn't fit, and dumps the rest off the edge."
        case .santa:
            "Santa flies in and waves a magic wand. A tornado spins up and sweeps across the screen, lifting snow off the bottom and off window tops, whirling it up and flinging it away."
        case .random:
            "A different helper is chosen each time."
        }
    }
}
