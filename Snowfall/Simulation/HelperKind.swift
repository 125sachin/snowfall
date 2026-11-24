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
    case ironMan
    case thor
    case random

    var id: String { rawValue }

    /// Helpers that can actually run. `.random` chooses one of these.
    static let concrete: [HelperKind] = [.jcb, .santa, .ironMan, .thor]

    var label: String {
        switch self {
        case .jcb: "JCB snow plow"
        case .santa: "Santa's magic tornado"
        case .ironMan: "Iron Man's eye lasers"
        case .thor: "Thor's hammer"
        case .random: "Surprise me"
        }
    }

    var shortLabel: String {
        switch self {
        case .jcb: "JCB"
        case .santa: "Santa"
        case .ironMan: "Iron Man"
        case .thor: "Thor"
        case .random: "Helper"
        }
    }

    var summary: String {
        switch self {
        case .jcb:
            "A JCB drives right to left along the bottom of the screen, pushing settled snow ahead of its blade. It slows under a heavy load, spills what doesn't fit, and dumps the rest off the edge."
        case .santa:
            "Santa flies in and waves a magic wand. A tornado spins up and sweeps across the screen, lifting snow off the bottom and off window tops, whirling it up and flinging it away."
        case .ironMan:
            "Iron Man flies in from the right and sweeps his eye lasers ahead of him as he heads left, melting settled snow into steam and vaporizing the flakes his beam crosses."
        case .thor:
            "Thor flies in and lands at two or three spots, heading left. At each one he brings Mjolnir down twice: the first blow cracks the ice layer, the second shatters it, with lightning, a shockwave and flying shards."
        case .random:
            "A different helper is chosen each time."
        }
    }
}
