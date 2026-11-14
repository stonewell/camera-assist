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
        case "nose", "head_joint": return .Nose
        case "neck", "neck_1_joint": return .Neck
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
        var canonicalJoints: [String: Joint] = [:]
        for (k, v) in joints {
            if let jt = JointType.from(key: k) {
                var j = v
                j.joint_type = jt
                canonicalJoints[jt.rawValue] = j
            }
        }
        self.joints = canonicalJoints
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

    public init(focalLengthMm: Float, hfovDeg: Float) {
        self.init(focal_length_mm: focalLengthMm, hfov_deg: hfovDeg)
    }

    public static let standardWide = CameraIntrinsics(focal_length_mm: 24.0, hfov_deg: 73.7)

    /// Derives camera intrinsics supporting optional 3x3 pinhole intrinsic matrix HFOV derivation.
    public static func from(
        focalLengthMm: Float? = nil,
        hfovDeg: Float? = nil,
        intrinsicMatrix: [Float]? = nil,
        imageWidth: Float? = nil
    ) -> CameraIntrinsics {
        if let hfov = hfovDeg {
            return CameraIntrinsics(focal_length_mm: focalLengthMm ?? 24.0, hfov_deg: hfov)
        }
        if let matrix = intrinsicMatrix, matrix.count >= 9, let w = imageWidth, w > 0 {
            let fx = matrix[0]
            if fx > 0 {
                let calculatedHfov = Float(2.0 * atan(Double(w) / (2.0 * Double(fx))) * 180.0 / .pi)
                return CameraIntrinsics(focal_length_mm: focalLengthMm ?? 24.0, hfov_deg: calculatedHfov)
            }
        }
        return CameraIntrinsics(focal_length_mm: focalLengthMm ?? 24.0, hfov_deg: 73.7)
    }
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

    /// Computes EV100 from photographic parameters: `log2(N^2 / t) - log2(ISO / 100) + bias`.
    public static func from(
        iso: Float,
        shutterSpeedSeconds: Float,
        lensAperture: Float = 1.8,
        exposureBias: Float = 0.0,
        evOverride: Float? = nil
    ) -> ExposureSummary {
        if let ev = evOverride {
            return ExposureSummary(iso: iso, shutter_speed_sec: shutterSpeedSeconds, ev: ev)
        }
        let n = Double(lensAperture > 0 ? lensAperture : 1.8)
        let t = Double(shutterSpeedSeconds > 0 ? shutterSpeedSeconds : 1.0 / 500.0)
        let isoVal = Double(iso > 0 ? iso : 100.0)
        let ev100 = log2((n * n) / t) - log2(isoVal / 100.0) + Double(exposureBias)
        return ExposureSummary(iso: iso, shutter_speed_sec: shutterSpeedSeconds, ev: Float(ev100))
    }

    public static func from(
        iso: Float,
        shutterSpeedSeconds: Double,
        lensAperture: Float = 1.8,
        exposureBias: Float = 0.0,
        evOverride: Float? = nil
    ) -> ExposureSummary {
        self.from(
            iso: iso,
            shutterSpeedSeconds: Float(shutterSpeedSeconds),
            lensAperture: lensAperture,
            exposureBias: exposureBias,
            evOverride: evOverride
        )
    }
}

/// Categorized primary lighting direction on the subject matching `compose-core::LightDirection`.
public enum LightDirection: String, Sendable, Codable, Equatable {
    case Front
    case Side
    case Backlit
    case Top
    case Overcast
    case Indoor
    case Unknown
}

/// Character and timing of ambient light matching `compose-core::LightQuality`.
public enum LightQuality: String, Sendable, Codable, Equatable {
    case Hard
    case Soft
    case GoldenHour
    case BlueHour
    case LowLight
}

/// Detailed frame luminance and backlight probe metrics.
public struct LuminanceMetrics: Sendable, Codable, Equatable {
    public var mean_luma: Float
    public var face_to_bg_ratio: Float
    public var highlight_clip_ratio: Float
    public var shadow_crush_ratio: Float
    public var is_backlit: Bool

    public init(
        mean_luma: Float = 0.5,
        face_to_bg_ratio: Float = 1.0,
        highlight_clip_ratio: Float = 0.0,
        shadow_crush_ratio: Float = 0.0,
        is_backlit: Bool = false
    ) {
        self.mean_luma = mean_luma
        self.face_to_bg_ratio = face_to_bg_ratio
        self.highlight_clip_ratio = highlight_clip_ratio
        self.shadow_crush_ratio = shadow_crush_ratio
        self.is_backlit = is_backlit
    }
}

/// Fused lighting environment data matching `compose-core::LightContext`.
public struct LightContext: Sendable, Codable, Equatable {
    public var direction: LightDirection
    public var quality: LightQuality
    public var sun_azimuth_deg: Float?
    public var sun_elevation_deg: Float?
    public var face_to_bg_ratio: Float?
    public var ev: Float
    public var confidence: Float

    public init(
        direction: LightDirection = .Front,
        quality: LightQuality = .Soft,
        sun_azimuth_deg: Float? = nil,
        sun_elevation_deg: Float? = nil,
        face_to_bg_ratio: Float? = 1.0,
        ev: Float = 12.0,
        confidence: Float = 0.8
    ) {
        self.direction = direction
        self.quality = quality
        self.sun_azimuth_deg = sun_azimuth_deg
        self.sun_elevation_deg = sun_elevation_deg
        self.face_to_bg_ratio = face_to_bg_ratio
        self.ev = ev
        self.confidence = confidence
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(direction, forKey: .direction)
        try container.encode(quality, forKey: .quality)
        if let az = sun_azimuth_deg {
            try container.encode(az, forKey: .sun_azimuth_deg)
        } else {
            try container.encodeNil(forKey: .sun_azimuth_deg)
        }
        if let el = sun_elevation_deg {
            try container.encode(el, forKey: .sun_elevation_deg)
        } else {
            try container.encodeNil(forKey: .sun_elevation_deg)
        }
        if let ratio = face_to_bg_ratio {
            try container.encode(ratio, forKey: .face_to_bg_ratio)
        } else {
            try container.encodeNil(forKey: .face_to_bg_ratio)
        }
        try container.encode(ev, forKey: .ev)
        try container.encode(confidence, forKey: .confidence)
    }

    private enum CodingKeys: String, CodingKey {
        case direction
        case quality
        case sun_azimuth_deg
        case sun_elevation_deg
        case face_to_bg_ratio
        case ev
        case confidence
    }

    public func toJSONString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard let str = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "PerceptionKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "UTF8 encoding failed"])
        }
        return str
    }

    public static func from(
        exposure: ExposureSummary,
        luminance: LuminanceMetrics? = nil,
        sunAzimuthDeg: Float? = nil,
        sunElevationDeg: Float? = nil,
        cameraAzimuthDeg: Float? = nil,
        confidence: Float = 0.85
    ) -> LightContext {
        let ev = exposure.ev

        let direction: LightDirection
        if let lum = luminance, lum.is_backlit || lum.face_to_bg_ratio < 0.45 {
            direction = .Backlit
        } else if let sunAz = sunAzimuthDeg, let camAz = cameraAzimuthDeg {
            var deltaAz = abs(sunAz - camAz).truncatingRemainder(dividingBy: 360.0)
            if deltaAz > 180.0 { deltaAz = 360.0 - deltaAz }
            if let sunEl = sunElevationDeg, sunEl > 65.0 {
                direction = .Top
            } else if deltaAz < 45.0 {
                direction = .Backlit
            } else if deltaAz > 135.0 {
                direction = .Front
            } else {
                direction = .Side
            }
        } else if ev < 7.0 {
            direction = .Indoor
        } else {
            direction = .Front
        }

        let quality: LightQuality
        if ev < 7.0 {
            quality = .LowLight
        } else if let sunEl = sunElevationDeg, sunEl >= 0.0 && sunEl <= 10.0 {
            quality = .GoldenHour
        } else if let sunEl = sunElevationDeg, sunEl < 0.0 && sunEl >= -6.0 {
            quality = .BlueHour
        } else if let lum = luminance, lum.highlight_clip_ratio > 0.05 {
            quality = .Hard
        } else {
            quality = .Soft
        }

        return LightContext(
            direction: direction,
            quality: quality,
            sun_azimuth_deg: sunAzimuthDeg,
            sun_elevation_deg: sunElevationDeg,
            face_to_bg_ratio: luminance?.face_to_bg_ratio,
            ev: ev,
            confidence: confidence
        )
    }
}

/// Unified perception bundle containing both geometric perception frame and lighting context.
public struct PerceptionBundle: Sendable, Codable, Equatable {
    public var frame: PerceptionFrame
    public var light: LightContext
    public var luminance: LuminanceMetrics?
    public var alignmentErrorMs: Double

    public init(
        frame: PerceptionFrame,
        light: LightContext = LightContext(),
        luminance: LuminanceMetrics? = nil,
        alignmentErrorMs: Double = 0.0
    ) {
        self.frame = frame
        self.light = light
        self.luminance = luminance
        self.alignmentErrorMs = alignmentErrorMs
    }
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
