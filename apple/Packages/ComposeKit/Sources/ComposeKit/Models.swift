import Foundation

/// Severity level for composition findings in Swift.
public enum ComposeSeverity: String, Codable, Sendable, Comparable {
    case good = "Good"
    case minor = "Minor"
    case major = "Major"
    case critical = "Critical"

    private var priorityOrder: Int {
        switch self {
        case .good: return 0
        case .minor: return 1
        case .major: return 2
        case .critical: return 3
        }
    }

    public static func < (lhs: ComposeSeverity, rhs: ComposeSeverity) -> Bool {
        lhs.priorityOrder < rhs.priorityOrder
    }
}

/// Photographic guidance action suggested by the engine.
public enum ComposeAction: Codable, Sendable, Equatable {
    case rotate(deg: Float, clockwise: Bool)
    case holdVertical
    case stepBack(steps: Int)
    case panLeft
    case panRight
    case tiltUp
    case tiltDown
    case good
}

/// Finding value type consumable by Swift UI layers.
public struct ComposeFinding: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var severity: ComposeSeverity
    public var hintKey: String

    public init(id: String, severity: ComposeSeverity, hintKey: String) {
        self.id = id
        self.severity = severity
        self.hintKey = hintKey
    }
}

/// Evaluated output per analyzed frame.
public struct ComposeOutput: Codable, Sendable, Equatable {
    public var activeFindingId: String?
    public var hintKey: String?
    public var isGoodToShoot: Bool
    public var rawFindingsCount: Int

    public init(
        activeFindingId: String? = nil,
        hintKey: String? = nil,
        isGoodToShoot: Bool = true,
        rawFindingsCount: Int = 0
    ) {
        self.activeFindingId = activeFindingId
        self.hintKey = hintKey
        self.isGoodToShoot = isGoodToShoot
        self.rawFindingsCount = rawFindingsCount
    }
}
