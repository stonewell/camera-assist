import Foundation
import CoreGraphics

/// Recognized body joint identifiers matching Vision and compose-core contracts.
public enum JointID: String, Sendable, CaseIterable, Codable {
    case nose, neck
    case lEye, rEye
    case lEar, rEar
    case lShoulder, rShoulder
    case lElbow, rElbow
    case lWrist, rWrist
    case root
    case lHip, rHip
    case lKnee, rKnee
    case lAnkle, rAnkle
}

/// Normalized joint representation [0, 1] relative to photo viewport.
public struct Joint: Sendable, Codable, Equatable {
    public var x: Float
    public var y: Float
    public var confidence: Float

    public init(x: Float, y: Float, confidence: Float) {
        self.x = x
        self.y = y
        self.confidence = confidence
    }

    public var point: CGPoint {
        CGPoint(x: CGFloat(x), y: CGFloat(y))
    }
}

/// Normalized bounding box with min/max bounds.
public struct NormalizedBox: Sendable, Codable, Equatable {
    public var min_x: Float
    public var min_y: Float
    public var max_x: Float
    public var max_y: Float

    public init(min_x: Float, min_y: Float, max_x: Float, max_y: Float) {
        self.min_x = min_x
        self.min_y = min_y
        self.max_x = max_x
        self.max_y = max_y
    }

    public init(rect: CGRect) {
        self.min_x = Float(rect.minX)
        self.min_y = Float(rect.minY)
        self.max_x = Float(rect.maxX)
        self.max_y = Float(rect.maxY)
    }

    public var cgRect: CGRect {
        CGRect(
            x: CGFloat(min_x),
            y: CGFloat(min_y),
            width: CGFloat(max_x - min_x),
            height: CGFloat(max_y - min_y)
        )
    }
}

/// Mask summary features extracted from person instance segmentation.
public struct MaskSummary: Sendable, Codable, Equatable {
    public var top_y: Float
    public var touches_top: Bool
    public var touches_bottom: Bool
    public var touches_left: Bool
    public var touches_right: Bool

    public init(
        top_y: Float,
        touches_top: Bool = false,
        touches_bottom: Bool = false,
        touches_left: Bool = false,
        touches_right: Bool = false
    ) {
        self.top_y = top_y
        self.touches_top = touches_top
        self.touches_bottom = touches_bottom
        self.touches_left = touches_left
        self.touches_right = touches_right
    }
}

/// Person subject perceived in the frame.
public struct Subject: Sendable, Codable, Equatable {
    public var id: String
    public var bbox: NormalizedBox
    public var joints: [String: Joint]
    public var shot_type: String
    public var facing: String
    public var is_group: Bool
    public var mask: MaskSummary?

    public init(
        id: String,
        bbox: NormalizedBox,
        joints: [String: Joint] = [:],
        shot_type: String = "FullBody",
        facing: String = "Front",
        is_group: Bool = false,
        mask: MaskSummary? = nil
    ) {
        self.id = id
        self.bbox = bbox
        self.joints = joints
        self.shot_type = shot_type
        self.facing = facing
        self.is_group = is_group
        self.mask = mask
    }
}

/// Device posture calculated from filtered 60Hz IMU motion.
public struct Posture: Sendable, Codable, Equatable {
    public var roll_deg: Float
    public var pitch_deg: Float
    public var elevation_deg: Float

    public init(roll_deg: Float, pitch_deg: Float, elevation_deg: Float? = nil) {
        self.roll_deg = roll_deg
        self.pitch_deg = pitch_deg
        self.elevation_deg = elevation_deg ?? pitch_deg
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

/// PerceptionFrame assembled by FrameSyncHub and consumed by compose-core.
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

    /// Serializes PerceptionFrame to JSON conforming to compose-core schema.
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
