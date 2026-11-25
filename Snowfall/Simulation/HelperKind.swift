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
    case spiderMan
    case penguin
    case snowballFight
    case snowman
    case sleigh
    case random

    var id: String { rawValue }

    /// Helpers that can actually run. `.random` chooses one of these.
    static let concrete: [HelperKind] = [.jcb, .santa, .ironMan, .thor, .spiderMan, .penguin, .snowballFight, .snowman, .sleigh]

    var label: String {
        switch self {
        case .jcb: "JCB snow plow"
        case .santa: "Santa's magic tornado"
        case .ironMan: "Iron Man's eye lasers"
        case .thor: "Thor's hammer"
        case .spiderMan: "Spider-Man's web swing"
        case .penguin: "Sliding penguin"
        case .snowballFight: "Snowball fight"
        case .snowman: "Snowman builder"
        case .sleigh: "Santa's sleigh flyby"
        case .random: "Surprise me"
        }
    }

    var shortLabel: String {
        switch self {
        case .jcb: "JCB"
        case .santa: "Santa"
        case .ironMan: "Iron Man"
        case .thor: "Thor"
        case .spiderMan: "Spider-Man"
        case .penguin: "Penguin"
        case .snowballFight: "Snowball Kid"
        case .snowman: "Snowman Builder"
        case .sleigh: "Sleigh"
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
        case .spiderMan:
            "Spider-Man swings in on webs from the right, heading left. His feet scrape a furrow through the snow at the bottom of each swing, he webs the biggest piles and yanks them away, and he spins a net to catch snow still in the air."
        case .penguin:
            "A penguin belly-slides along the bottom of the screen from right to left, ploughing a strip of the floor clear and kicking up snow."
        case .snowballFight:
            "A kid walks along the floor throwing snowballs in arcs. They blast piles of snow away and splat on windows, leaving marks that fade."
        case .snowman:
            "A kid rolls a snowball along the floor, picking up all the snow in its path so it grows. Then they stack it into a snowman that stays for about a minute."
        case .sleigh:
            "Santa's sleigh and reindeer sweep across the screen. The downdraught blows snow off the surfaces below, tosses the falling flakes around, and leaves a glitter trail."
        case .random:
            "A different helper is chosen each time."
        }
    }
}
