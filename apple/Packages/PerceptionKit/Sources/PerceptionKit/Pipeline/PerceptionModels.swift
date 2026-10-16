import Foundation
import CoreGraphics

/// Canonical body joint identifiers matching `compose-core::JointType` (19 joints: 17 COCO + Neck + Root).
public enum JointType: String, Sendable, CaseIterable, Codable {
    case Nose
    case Neck
    case Root
    case LeftEye
    case RightEye
    case LeftEar
    case RightEar
    case LeftShoulder
    case RightShoulder
    case LeftElbow
    case RightElbow
    case LeftWrist
    case RightWrist
    case LeftHip
    case RightHip
    case LeftKnee
    case RightKnee
    case LeftAnkle
    case RightAnkle

    /// Maps legacy shorthand or Vision joint keys to canonical PascalCase `JointType`.
    public static func from(key: String) -> JointType? {
        if let exact = JointType(rawValue: key) {
            return exact
        }
        switch key {
        case "nose": return .Nose
        case "neck": return .Neck
        case "root": return .Root
        case "lEye", "left_eye_joint": return .LeftEye
        case "rEye", "right_eye_joint": return .RightEye
        case "lEar", "left_ear_joint": return .LeftEar
        case "rEar", "right_ear_joint": return .RightEar
        case "lShoulder", "left_shoulder_1_joint": return .LeftShoulder
        case "rShoulder", "right_shoulder_1_joint": return .RightShoulder
        case "lElbow", "left_forearm_joint": return .LeftElbow
        case "rElbow", "right_forearm_joint": return .RightElbow
        case "lWrist", "left_hand_joint": return .LeftWrist
        case "rWrist", "right_hand_joint": return .RightWrist
        case "lHip", "left_upLeg_joint": return .LeftHip
        case "rHip", "right_upLeg_joint": return .RightHip
        case "lKnee", "left_leg_joint": return .LeftKnee
        case "rKnee", "right_leg_joint": return .RightKnee
        case "lAnkle", "left_foot_joint": return .LeftAnkle
        case "rAnkle", "right_foot_joint": return .RightAnkle
        default: return nil
        }
    }
}

public typealias JointID = JointType

/// 2D point in normalized screen coordinates [0.0, 1.0] (origin top-left), matching `compose-core::NormalizedPoint`.
public struct NormalizedPoint: Sendable, Codable, Equatable {
    public var x: Float
    public var y: Float

    public init(x: Float, y: Float) {
        self.x = x
        self.y = y
    }

    public var cgPoint: CGPoint {
        CGPoint(x: CGFloat(x), y: CGFloat(y))
    }
}

/// Normalized joint representation [0, 1] relative to photo viewport, matching `compose-core::Joint`.
public struct Joint: Sendable, Codable, Equatable {
    public var joint_type: JointType
    public var point: NormalizedPoint
    public var confidence: Float

    public init(joint_type: JointType = .Nose, point: NormalizedPoint, confidence: Float) {
        self.joint_type = joint_type
        self.point = point
        self.confidence = confidence
    }

    public init(joint_type: JointType = .Nose, x: Float, y: Float, confidence: Float) {
        self.joint_type = joint_type
        self.point = NormalizedPoint(x: x, y: y)
        self.confidence = confidence
    }

    public var x: Float {
        get { point.x }
        set { point.x = newValue }
    }

    public var y: Float {
        get { point.y }
        set { point.y = newValue }
    }
}

/// Normalized bounding box matching `compose-core::NormalizedRect` (`x`, `y`, `width`, `height`).
public struct NormalizedBox: Sendable, Codable, Equatable {
    public var x: Float
    public var y: Float
    public var width: Float
    public var height: Float

    public init(x: Float, y: Float, width: Float, height: Float) {
        self.x = x
        self.y = y
        self.width = max(0.0, width)
        self.height = max(0.0, height)
    }

    public init(min_x: Float, min_y: Float, max_x: Float, max_y: Float) {
        self.x = min_x
        self.y = min_y
        self.width = max(0.0, max_x - min_x)
        self.height = max(0.0, max_y - min_y)
    }

    public init(rect: CGRect) {
        self.x = Float(rect.minX)
        self.y = Float(rect.minY)
        self.width = Float(max(0.0, rect.width))
        self.height = Float(max(0.0, rect.height))
    }

    public var min_x: Float { x }
    public var min_y: Float { y }
    public var max_x: Float { x + width }
    public var max_y: Float { y + height }

    public var cgRect: CGRect {
        CGRect(
            x: CGFloat(x),
            y: CGFloat(y),
            width: CGFloat(width),
            height: CGFloat(height)
        )
    }
}

public typealias NormalizedRect = NormalizedBox

/// Mask summary features extracted from person instance segmentation, matching `compose-core::MaskSummary`.
public struct MaskSummary: Sendable, Codable, Equatable {
    public var top_y: Float
    public var bottom_y: Float
    public var head_cols: [Float]
    public var torso_cols: [Float]
    public var leg_cols: [Float]
    public var touches_top: Bool
    public var touches_bottom: Bool
    public var touches_left: Bool
    public var touches_right: Bool

    public init(
        top_y: Float,
        bottom_y: Float = 1.0,
        head_cols: [Float] = [0.0, 0.0],
        torso_cols: [Float] = [0.0, 0.0],
        leg_cols: [Float] = [0.0, 0.0],
        touches_top: Bool = false,
        touches_bottom: Bool = false,
        touches_left: Bool = false,
        touches_right: Bool = false
    ) {
        self.top_y = top_y
        self.bottom_y = bottom_y
        self.head_cols = head_cols.count == 2 ? head_cols : [0.0, 0.0]
        self.torso_cols = torso_cols.count == 2 ? torso_cols : [0.0, 0.0]
        self.leg_cols = leg_cols.count == 2 ? leg_cols : [0.0, 0.0]
        self.touches_top = touches_top
        self.touches_bottom = touches_bottom
        self.touches_left = touches_left
        self.touches_right = touches_right
    }
}

/// Person subject perceived in the frame, matching `compose-core::Subject` 100%.
public struct Subject: Sendable, Codable, Equatable {
    public var id: UInt32
    public var bounds: NormalizedBox
    public var joints: [String: Joint]
    public var facing: String
    public var shot_type: String
    public var confidence: Float
    public var is_group: Bool
    public var mask_summary: MaskSummary?

    public init(
        id: UInt32 = 1,
        bounds: NormalizedBox,
        joints: [String: Joint] = [:],
        facing: String = "Frontal",
        shot_type: String = "FullBody",
        confidence: Float = 1.0,
        is_group: Bool = false,
        mask_summary: MaskSummary? = nil
    ) {
        self.id = id
        self.bounds = bounds
        self.joints = joints
        self.facing = facing == "Front" ? "Frontal" : facing
        self.shot_type = shot_type
        self.confidence = confidence
        self.is_group = is_group
        self.mask_summary = mask_summary
    }

    public init(
        id: String,
        bbox: NormalizedBox,
        joints: [String: Joint] = [:],
        shot_type: String = "FullBody",
        facing: String = "Frontal",
        confidence: Float = 1.0,
        is_group: Bool = false,
        mask: MaskSummary? = nil
    ) {
        let numericId = UInt32(id.filter(\.isNumber)) ?? 1
        self.init(
            id: numericId,
            bounds: bbox,
            joints: joints,
            facing: facing,
            shot_type: shot_type,
            confidence: confidence,
            is_group: is_group,
            mask_summary: mask
        )
    }

    public var bbox: NormalizedBox {
        get { bounds }
        set { bounds = newValue }
    }

    public var mask: MaskSummary? {
        get { mask_summary }
        set { mask_summary = newValue }
    }
}

/// Device posture calculated from filtered 60Hz IMU motion, matching `compose-core::Posture`.
public struct Posture: Sendable, Codable, Equatable {
    public var roll_deg: Float
    public var pitch_deg: Float
    public var elevation_deg: Float
    public var angular_speed: Float
    public var is_flatish: Bool

    public init(
        roll_deg: Float,
        pitch_deg: Float,
        elevation_deg: Float? = nil,
        angular_speed: Float = 0.0,
        is_flatish: Bool = false
    ) {
        self.roll_deg = roll_deg
        self.pitch_deg = pitch_deg
        self.elevation_deg = elevation_deg ?? pitch_deg
        self.angular_speed = angular_speed
        self.is_flatish = is_flatish
    }

    public static let zero = Posture(roll_deg: 0, pitch_deg: 0, elevation_deg: 0)
}

/// Lens intrinsics.
public struct CameraIntrinsics: Sendable, Codable, Equatable {
    public var focal_length_mm: Float
    public var hfov_deg: Float

    public init(focal_length_mm: Float = 24.0, hfov_deg: Float = 73.7) {
        self.focal_length_mm = focal_length_mm
        self.hfov_deg = hfov_deg
    }

    public static let standardWide = CameraIntrinsics(focal_length_mm: 24.0, hfov_deg: 73.7)
}

/// Exposure metrics.
public struct ExposureSummary: Sendable, Codable, Equatable {
    public var iso: Float
    public var shutter_speed_sec: Float
    public var ev: Float

    public init(iso: Float = 100.0, shutter_speed_sec: Float = 1.0 / 500.0, ev: Float = 12.0) {
        self.iso = iso
        self.shutter_speed_sec = shutter_speed_sec
        self.ev = ev
    }

    public static let daylight = ExposureSummary()
}

/// PerceptionFrame assembled by FrameSyncHub and consumed by `compose-core::Frame`.
public struct PerceptionFrame: Sendable, Codable, Equatable {
    public var t: Double
    public var subjects: [Subject]
    public var primary_subject_index: Int?
    public var posture: Posture
    public var camera: CameraIntrinsics
    public var exposure: ExposureSummary

    public init(
        t: Double,
        subjects: [Subject] = [],
        primary_subject_index: Int? = nil,
        posture: Posture = .zero,
        camera: CameraIntrinsics = .standardWide,
        exposure: ExposureSummary = .daylight
    ) {
        self.t = t
        self.subjects = subjects
        self.primary_subject_index = primary_subject_index ?? (subjects.isEmpty ? nil : 0)
        self.posture = posture
        self.camera = camera
        self.exposure = exposure
    }

    /// Serializes PerceptionFrame to JSON conforming to `compose-core::Frame` schema.
    public func toJSONString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard let str = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "PerceptionKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "UTF8 encoding failed"])
        }
        return str
    }
}
