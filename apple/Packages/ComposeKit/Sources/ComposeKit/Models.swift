import Foundation

/// Severity level for composition findings in Swift.
public enum ComposeSeverity: String, Codable, Sendable, Comparable {
    case good = "Good"
    case minor = "Minor"
    case major = "Major"
    case critical = "Critical"

    public init(ffi: SeverityFfi) {
        switch ffi {
        case .good: self = .good
        case .minor: self = .minor
        case .major: self = .major
        case .critical: self = .critical
        }
    }

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

/// Target audience of the instruction.
public enum ComposeAudience: String, Codable, Sendable {
    case photographer = "Photographer"
    case subject = "Subject"

    public init(ffi: AudienceFfi) {
        switch ffi {
        case .photographer: self = .photographer
        case .subject: self = .subject
        }
    }
}

/// Photographic guidance action suggested by the engine.
public enum ComposeAction: Codable, Sendable, Equatable {
    case rotate(deg: Float, clockwise: Bool)
    case holdVertical
    case lowerPhone
    case stepBack(steps: Int)
    case stepForward(steps: Int)
    case panLeft
    case panRight
    case tiltUp
    case tiltDown
    case switchZoom(factor: Float)
    case enableFill
    case cleanLens
    case moveToShade
    case turnSubject(deg: Float)
    case useNightMode
    case good

    public init(ffi: ActionFfi) {
        switch ffi {
        case let .rotate(deg, clockwise):
            self = .rotate(deg: deg, clockwise: clockwise)
        case .holdVertical:
            self = .holdVertical
        case .lowerPhone:
            self = .lowerPhone
        case let .stepBack(steps):
            self = .stepBack(steps: Int(steps))
        case let .stepForward(steps):
            self = .stepForward(steps: Int(steps))
        case .panLeft:
            self = .panLeft
        case .panRight:
            self = .panRight
        case .tiltUp:
            self = .tiltUp
        case .tiltDown:
            self = .tiltDown
        case let .switchZoom(factor):
            self = .switchZoom(factor: factor)
        case .enableFill:
            self = .enableFill
        case .cleanLens:
            self = .cleanLens
        case .moveToShade:
            self = .moveToShade
        case let .turnSubject(deg):
            self = .turnSubject(deg: deg)
        case .useNightMode:
            self = .useNightMode
        case .good:
            self = .good
        }
    }
}

/// Localized prompt strings for a specific finding action or condition.
public struct ComposeHint: Codable, Sendable, Equatable {
    public var primary: String
    public var secondary: String
    public var spoken: String

    public init(primary: String = "", secondary: String = "", spoken: String = "") {
        self.primary = primary
        self.secondary = secondary
        self.spoken = spoken
    }

    public init(ffi: HintItemFfi) {
        self.primary = ffi.primary
        self.secondary = ffi.secondary
        self.spoken = ffi.spoken
    }
}

public typealias HintItem = ComposeHint

/// Finding value type consumable by Swift UI layers.
public struct ComposeFinding: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var severity: ComposeSeverity
    public var audience: ComposeAudience
    public var primaryAction: ComposeAction
    public var secondaryAction: ComposeAction?
    public var hintKey: String
    public var hint: ComposeHint
    public var hintText: String
    public var value: Float?
    public var target: Float?

    public init(
        id: String,
        severity: ComposeSeverity,
        audience: ComposeAudience = .photographer,
        primaryAction: ComposeAction = .good,
        secondaryAction: ComposeAction? = nil,
        hintKey: String,
        hint: ComposeHint = ComposeHint(),
        hintText: String = "",
        value: Float? = nil,
        target: Float? = nil
    ) {
        self.id = id
        self.severity = severity
        self.audience = audience
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
        self.hintKey = hintKey
        self.hint = hint
        self.hintText = hintText.isEmpty ? hint.primary : hintText
        self.value = value
        self.target = target
    }

    public init(ffi: FindingFfi) {
        self.id = ffi.id
        self.severity = ComposeSeverity(ffi: ffi.severity)
        self.audience = ComposeAudience(ffi: ffi.audience)
        self.primaryAction = ComposeAction(ffi: ffi.primaryAction)
        self.secondaryAction = ffi.secondaryAction.map { ComposeAction(ffi: $0) }
        self.hintKey = ffi.hintKey
        self.hint = ComposeHint(ffi: ffi.hint)
        self.hintText = ffi.hintText
        self.value = ffi.value
        self.target = ffi.target
    }
}

/// Evaluated output per analyzed frame.
public struct ComposeOutput: Codable, Sendable, Equatable {
    public var activeFindingId: String?
    public var severity: ComposeSeverity
    public var audience: ComposeAudience?
    public var primaryAction: ComposeAction?
    public var secondaryAction: ComposeAction?
    public var value: Float?
    public var target: Float?
    public var hintKey: String?
    public var hint: ComposeHint?
    public var hintText: String?
    public var isGoodToShoot: Bool
    public var rawFindingsCount: Int

    public init(
        activeFindingId: String? = nil,
        severity: ComposeSeverity = .good,
        audience: ComposeAudience? = nil,
        primaryAction: ComposeAction? = nil,
        secondaryAction: ComposeAction? = nil,
        value: Float? = nil,
        target: Float? = nil,
        hintKey: String? = nil,
        hint: ComposeHint? = nil,
        hintText: String? = nil,
        isGoodToShoot: Bool = true,
        rawFindingsCount: Int = 0
    ) {
        self.activeFindingId = activeFindingId
        self.severity = severity
        self.audience = audience
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
        self.value = value
        self.target = target
        self.hintKey = hintKey
        self.hint = hint
        self.hintText = hintText ?? hint?.primary
        self.isGoodToShoot = isGoodToShoot
        self.rawFindingsCount = rawFindingsCount
    }

    public init(ffi: LiveOutputFfi) {
        self.activeFindingId = ffi.activeFindingId
        self.severity = ComposeSeverity(ffi: ffi.severity)
        self.audience = ffi.audience.map { ComposeAudience(ffi: $0) }
        self.primaryAction = ffi.primaryAction.map { ComposeAction(ffi: $0) }
        self.secondaryAction = ffi.secondaryAction.map { ComposeAction(ffi: $0) }
        self.value = ffi.value
        self.target = ffi.target
        self.hintKey = ffi.hintKey
        self.hint = ffi.hint.map { ComposeHint(ffi: $0) }
        self.hintText = ffi.hintText
        self.isGoodToShoot = ffi.isGoodToShoot
        self.rawFindingsCount = Int(ffi.rawFindingsCount)
    }
}
