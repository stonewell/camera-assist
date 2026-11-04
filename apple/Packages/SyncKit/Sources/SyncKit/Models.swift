import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Pure Swift normalized point [0.0, 1.0]
public struct NormalizedPoint: Codable, Equatable, Sendable {
    public var x: Float
    public var y: Float

    public init(x: Float, y: Float) {
        self.x = x
        self.y = y
    }
}

/// Pure Swift normalized bounding box [0.0, 1.0]
public struct NormalizedRect: Codable, Equatable, Sendable {
    public var x: Float
    public var y: Float
    public var width: Float
    public var height: Float

    public init(x: Float, y: Float, width: Float, height: Float) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var center: NormalizedPoint {
        NormalizedPoint(x: x + width / 2.0, y: y + height / 2.0)
    }

    #if canImport(CoreGraphics)
    public var cgRect: CGRect {
        CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
    }

    public init(cgRect: CGRect) {
        self.x = Float(cgRect.origin.x)
        self.y = Float(cgRect.origin.y)
        self.width = Float(cgRect.size.width)
        self.height = Float(cgRect.size.height)
    }
    #endif
}

/// Pure Swift 2D offset vector for camera registration and alignment.
public struct AlignmentOffset: Codable, Equatable, Sendable {
    public var dx: Double
    public var dy: Double

    public init(dx: Double = 0.0, dy: Double = 0.0) {
        self.dx = dx
        self.dy = dy
    }

    #if canImport(CoreGraphics)
    public var cgVector: CGVector {
        CGVector(dx: dx, dy: dy)
    }

    public init(cgVector: CGVector) {
        self.dx = Double(cgVector.dx)
        self.dy = Double(cgVector.dy)
    }
    #endif
}

/// Session status for App Clip stranger assist mode.
public enum SyncStatus: String, Codable, Sendable, Equatable {
    case pending = "pending"
    case connecting = "connecting"
    case ready = "ready"
    case captured = "captured"
    case syncing = "syncing"
    case completed = "completed"
    case expired = "expired"
    case failed = "failed"
}

/// Session role in the ephemeral assist interaction.
public enum SessionRole: String, Codable, Sendable, Equatable {
    case owner = "owner"
    case guest = "guest"
    case relay = "relay"
}

/// End-to-end encrypted envelope for transport over relay / WebSocket / Bonjour / AirDrop.
public struct EncryptionEnvelope: Codable, Equatable, Sendable {
    public var keyId: String
    public var nonceBase64: String
    public var ciphertext: Data
    public var tagBase64: String

    public init(keyId: String = "", nonceBase64: String, ciphertext: Data, tagBase64: String) {
        self.keyId = keyId
        self.nonceBase64 = nonceBase64
        self.ciphertext = ciphertext
        self.tagBase64 = tagBase64
    }
}

/// Reference visual package sent by owner device to App Clip guest device (~30 KB).
public struct ReferencePackage: Codable, Equatable, Sendable {
    public var sessionId: UUID
    public var createdAt: Date
    public var expiresAt: Date
    public var ownerDeviceToken: String
    public var promptKey: String
    public var targetFraming: NormalizedRect
    public var compositionType: String
    public var thumbnailJpegData: Data?
    public var registrationGrayData: Data?
    public var targetZoomFactor: Double
    public var captureAngle: Double
    public var elevationDeg: Double
    public var rollDeg: Double
    public var slots: [NormalizedRect]
    public var languageCode: String
    public var autoBurstEnabled: Bool
    public var previewThumbnailData: Data?

    public init(
        sessionId: UUID = UUID(),
        createdAt: Date = Date(),
        expiresAt: Date = Date().addingTimeInterval(600.0), // 10 minutes default TTL
        ownerDeviceToken: String = "",
        promptKey: String = "rule_of_thirds",
        targetFraming: NormalizedRect = NormalizedRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
        compositionType: String = "portrait",
        thumbnailJpegData: Data? = nil,
        registrationGrayData: Data? = nil,
        targetZoomFactor: Double = 1.0,
        captureAngle: Double = 0.0,
        elevationDeg: Double = 0.0,
        rollDeg: Double = 0.0,
        slots: [NormalizedRect] = [],
        languageCode: String = "en",
        autoBurstEnabled: Bool = false,
        previewThumbnailData: Data? = nil
    ) {
        self.sessionId = sessionId
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.ownerDeviceToken = ownerDeviceToken
        self.promptKey = promptKey
        self.targetFraming = targetFraming
        self.compositionType = compositionType
        self.thumbnailJpegData = thumbnailJpegData ?? previewThumbnailData
        self.registrationGrayData = registrationGrayData
        self.targetZoomFactor = targetZoomFactor
        self.captureAngle = captureAngle
        self.elevationDeg = elevationDeg
        self.rollDeg = rollDeg
        self.slots = slots
        self.languageCode = languageCode
        self.autoBurstEnabled = autoBurstEnabled
        self.previewThumbnailData = previewThumbnailData ?? thumbnailJpegData
    }

    /// Legacy initializer compatibility for existing AppClipStub and baseline tests.
    public init(
        sessionId: UUID = UUID(),
        ownerDeviceToken: String,
        promptKey: String,
        targetFraming: NormalizedRect,
        compositionType: String,
        previewThumbnailData: Data? = nil,
        createdTimestamp: Double,
        expiresTimestamp: Double
    ) {
        self.sessionId = sessionId
        self.createdAt = Date(timeIntervalSince1970: createdTimestamp)
        self.expiresAt = Date(timeIntervalSince1970: expiresTimestamp)
        self.ownerDeviceToken = ownerDeviceToken
        self.promptKey = promptKey
        self.targetFraming = targetFraming
        self.compositionType = compositionType
        self.thumbnailJpegData = previewThumbnailData
        self.registrationGrayData = nil
        self.targetZoomFactor = 1.0
        self.captureAngle = 0.0
        self.elevationDeg = 0.0
        self.rollDeg = 0.0
        self.slots = []
        self.languageCode = "en"
        self.autoBurstEnabled = false
        self.previewThumbnailData = previewThumbnailData
    }

    public var createdTimestamp: Double {
        createdAt.timeIntervalSince1970
    }

    public var expiresTimestamp: Double {
        expiresAt.timeIntervalSince1970
    }

    public var isExpired: Bool {
        Date() > expiresAt
    }

    public var sessionIdString: String {
        sessionId.uuidString
    }

    private enum CodingKeys: String, CodingKey {
        case sessionId
        case createdAt
        case expiresAt
        case createdTimestamp
        case expiresTimestamp
        case ownerDeviceToken
        case promptKey
        case targetFraming
        case compositionType
        case thumbnailJpegData
        case registrationGrayData
        case targetZoomFactor
        case captureAngle
        case elevationDeg
        case rollDeg
        case slots
        case languageCode
        case autoBurstEnabled
        case previewThumbnailData
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Session ID decoding (support UUID or UUID string)
        if let id = try? container.decode(UUID.self, forKey: .sessionId) {
            self.sessionId = id
        } else if let idStr = try? container.decode(String.self, forKey: .sessionId),
                  let id = UUID(uuidString: idStr) {
            self.sessionId = id
        } else {
            self.sessionId = UUID()
        }

        // Timestamp decoding with fallback between Date and Double timestamp
        if let d = try? container.decode(Date.self, forKey: .createdAt) {
            self.createdAt = d
        } else if let ts = try? container.decode(Double.self, forKey: .createdTimestamp) {
            self.createdAt = Date(timeIntervalSince1970: ts)
        } else {
            self.createdAt = Date()
        }

        if let d = try? container.decode(Date.self, forKey: .expiresAt) {
            self.expiresAt = d
        } else if let ts = try? container.decode(Double.self, forKey: .expiresTimestamp) {
            self.expiresAt = Date(timeIntervalSince1970: ts)
        } else {
            self.expiresAt = self.createdAt.addingTimeInterval(600.0)
        }

        self.ownerDeviceToken = (try? container.decode(String.self, forKey: .ownerDeviceToken)) ?? ""
        self.promptKey = (try? container.decode(String.self, forKey: .promptKey)) ?? "rule_of_thirds"
        self.targetFraming = (try? container.decode(NormalizedRect.self, forKey: .targetFraming)) ?? NormalizedRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        self.compositionType = (try? container.decode(String.self, forKey: .compositionType)) ?? "portrait"

        let thumb = try? container.decode(Data.self, forKey: .thumbnailJpegData)
        let prev = try? container.decode(Data.self, forKey: .previewThumbnailData)
        self.thumbnailJpegData = thumb ?? prev
        self.previewThumbnailData = prev ?? thumb

        self.registrationGrayData = try? container.decode(Data.self, forKey: .registrationGrayData)
        self.targetZoomFactor = (try? container.decode(Double.self, forKey: .targetZoomFactor)) ?? 1.0
        self.captureAngle = (try? container.decode(Double.self, forKey: .captureAngle)) ?? 0.0
        self.elevationDeg = (try? container.decode(Double.self, forKey: .elevationDeg)) ?? 0.0
        self.rollDeg = (try? container.decode(Double.self, forKey: .rollDeg)) ?? 0.0
        self.slots = (try? container.decode([NormalizedRect].self, forKey: .slots)) ?? []
        self.languageCode = (try? container.decode(String.self, forKey: .languageCode)) ?? "en"
        self.autoBurstEnabled = (try? container.decode(Bool.self, forKey: .autoBurstEnabled)) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionId, forKey: .sessionId)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(expiresAt, forKey: .expiresAt)
        try container.encode(createdTimestamp, forKey: .createdTimestamp)
        try container.encode(expiresTimestamp, forKey: .expiresTimestamp)
        try container.encode(ownerDeviceToken, forKey: .ownerDeviceToken)
        try container.encode(promptKey, forKey: .promptKey)
        try container.encode(targetFraming, forKey: .targetFraming)
        try container.encode(compositionType, forKey: .compositionType)
        try container.encodeIfPresent(thumbnailJpegData, forKey: .thumbnailJpegData)
        try container.encodeIfPresent(registrationGrayData, forKey: .registrationGrayData)
        try container.encode(targetZoomFactor, forKey: .targetZoomFactor)
        try container.encode(captureAngle, forKey: .captureAngle)
        try container.encode(elevationDeg, forKey: .elevationDeg)
        try container.encode(rollDeg, forKey: .rollDeg)
        try container.encode(slots, forKey: .slots)
        try container.encode(languageCode, forKey: .languageCode)
        try container.encode(autoBurstEnabled, forKey: .autoBurstEnabled)
        try container.encodeIfPresent(previewThumbnailData, forKey: .previewThumbnailData)
    }
}

/// Photographic capture package produced by App Clip guest camera, returned to owner.
public struct CapturePackage: Codable, Equatable, Sendable {
    public var sessionId: UUID
    public var photoId: String
    public var sequenceIndex: Int
    public var capturedAt: Date
    public var fullPhotoData: Data
    public var previewThumbnailData: Data
    public var alignmentOffset: AlignmentOffset
    public var alignmentScale: Double
    public var wasReadyState: Bool
    public var deviceModel: String
    public var cameraPitch: Float
    public var cameraRoll: Float
    public var focalLengthMm: Float
    public var clientNonce: String

    public init(
        sessionId: UUID,
        photoId: String = UUID().uuidString,
        sequenceIndex: Int = 0,
        capturedAt: Date = Date(),
        fullPhotoData: Data,
        previewThumbnailData: Data = Data(),
        alignmentOffset: AlignmentOffset = AlignmentOffset(),
        alignmentScale: Double = 1.0,
        wasReadyState: Bool = true,
        deviceModel: String = "iPhone",
        cameraPitch: Float = 0.0,
        cameraRoll: Float = 0.0,
        focalLengthMm: Float = 24.0,
        clientNonce: String = UUID().uuidString
    ) {
        self.sessionId = sessionId
        self.photoId = photoId
        self.sequenceIndex = sequenceIndex
        self.capturedAt = capturedAt
        self.fullPhotoData = fullPhotoData
        self.previewThumbnailData = previewThumbnailData
        self.alignmentOffset = alignmentOffset
        self.alignmentScale = alignmentScale
        self.wasReadyState = wasReadyState
        self.deviceModel = deviceModel
        self.cameraPitch = cameraPitch
        self.cameraRoll = cameraRoll
        self.focalLengthMm = focalLengthMm
        self.clientNonce = clientNonce
    }

    /// Legacy initializer compatibility for existing tests.
    public init(
        sessionId: UUID,
        capturedPhotoJpeg: Data,
        cameraPitch: Float,
        cameraRoll: Float,
        focalLengthMm: Float,
        capturedTimestamp: Double = Date().timeIntervalSince1970,
        clientNonce: String = UUID().uuidString
    ) {
        self.sessionId = sessionId
        self.photoId = UUID().uuidString
        self.sequenceIndex = 0
        self.capturedAt = Date(timeIntervalSince1970: capturedTimestamp)
        self.fullPhotoData = capturedPhotoJpeg
        self.previewThumbnailData = Data()
        self.alignmentOffset = AlignmentOffset()
        self.alignmentScale = 1.0
        self.wasReadyState = true
        self.deviceModel = "iPhone"
        self.cameraPitch = cameraPitch
        self.cameraRoll = cameraRoll
        self.focalLengthMm = focalLengthMm
        self.clientNonce = clientNonce
    }

    public var capturedPhotoJpeg: Data {
        fullPhotoData
    }

    public var capturedTimestamp: Double {
        capturedAt.timeIntervalSince1970
    }

    private enum CodingKeys: String, CodingKey {
        case sessionId
        case photoId
        case sequenceIndex
        case capturedAt
        case capturedTimestamp
        case fullPhotoData
        case capturedPhotoJpeg
        case previewThumbnailData
        case alignmentOffset
        case alignmentScale
        case wasReadyState
        case deviceModel
        case cameraPitch
        case cameraRoll
        case focalLengthMm
        case clientNonce
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let id = try? container.decode(UUID.self, forKey: .sessionId) {
            self.sessionId = id
        } else if let idStr = try? container.decode(String.self, forKey: .sessionId),
                  let id = UUID(uuidString: idStr) {
            self.sessionId = id
        } else {
            self.sessionId = UUID()
        }

        self.photoId = (try? container.decode(String.self, forKey: .photoId)) ?? UUID().uuidString
        self.sequenceIndex = (try? container.decode(Int.self, forKey: .sequenceIndex)) ?? 0

        if let d = try? container.decode(Date.self, forKey: .capturedAt) {
            self.capturedAt = d
        } else if let ts = try? container.decode(Double.self, forKey: .capturedTimestamp) {
            self.capturedAt = Date(timeIntervalSince1970: ts)
        } else {
            self.capturedAt = Date()
        }

        let full = try? container.decode(Data.self, forKey: .fullPhotoData)
        let jpeg = try? container.decode(Data.self, forKey: .capturedPhotoJpeg)
        guard let photoData = full ?? jpeg else {
            throw DecodingError.dataCorruptedError(forKey: .fullPhotoData, in: container, debugDescription: "Missing photo image payload")
        }
        self.fullPhotoData = photoData

        self.previewThumbnailData = (try? container.decode(Data.self, forKey: .previewThumbnailData)) ?? Data()
        self.alignmentOffset = (try? container.decode(AlignmentOffset.self, forKey: .alignmentOffset)) ?? AlignmentOffset()
        self.alignmentScale = (try? container.decode(Double.self, forKey: .alignmentScale)) ?? 1.0
        self.wasReadyState = (try? container.decode(Bool.self, forKey: .wasReadyState)) ?? true
        self.deviceModel = (try? container.decode(String.self, forKey: .deviceModel)) ?? "iPhone"
        self.cameraPitch = (try? container.decode(Float.self, forKey: .cameraPitch)) ?? 0.0
        self.cameraRoll = (try? container.decode(Float.self, forKey: .cameraRoll)) ?? 0.0
        self.focalLengthMm = (try? container.decode(Float.self, forKey: .focalLengthMm)) ?? 24.0
        self.clientNonce = (try? container.decode(String.self, forKey: .clientNonce)) ?? UUID().uuidString
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionId, forKey: .sessionId)
        try container.encode(photoId, forKey: .photoId)
        try container.encode(sequenceIndex, forKey: .sequenceIndex)
        try container.encode(capturedAt, forKey: .capturedAt)
        try container.encode(capturedTimestamp, forKey: .capturedTimestamp)
        try container.encode(fullPhotoData, forKey: .fullPhotoData)
        try container.encode(fullPhotoData, forKey: .capturedPhotoJpeg)
        try container.encode(previewThumbnailData, forKey: .previewThumbnailData)
        try container.encode(alignmentOffset, forKey: .alignmentOffset)
        try container.encode(alignmentScale, forKey: .alignmentScale)
        try container.encode(wasReadyState, forKey: .wasReadyState)
        try container.encode(deviceModel, forKey: .deviceModel)
        try container.encode(cameraPitch, forKey: .cameraPitch)
        try container.encode(cameraRoll, forKey: .cameraRoll)
        try container.encode(focalLengthMm, forKey: .focalLengthMm)
        try container.encode(clientNonce, forKey: .clientNonce)
    }
}

/// Message payload transferred across SyncTransport protocol.
public enum SyncMessage: Codable, Equatable, Sendable {
    case handshake(HandshakePayload)
    case handshakeAck(HandshakeAckPayload)
    case referencePackageEnvelope(EncryptionEnvelope)
    case capturePackageEnvelope(EncryptionEnvelope)
    case statusUpdate(SyncStatus)
    case heartbeat(timestamp: Double)
    case error(code: Int, message: String)
    case close(reason: String)
}

public struct HandshakePayload: Codable, Equatable, Sendable {
    public var sessionId: UUID
    public var token: String
    public var clientRole: SessionRole
    public var publicKeyBase64: String?
    public var timestamp: Double

    public init(
        sessionId: UUID,
        token: String,
        clientRole: SessionRole,
        publicKeyBase64: String? = nil,
        timestamp: Double = Date().timeIntervalSince1970
    ) {
        self.sessionId = sessionId
        self.token = token
        self.clientRole = clientRole
        self.publicKeyBase64 = publicKeyBase64
        self.timestamp = timestamp
    }
}

public struct HandshakeAckPayload: Codable, Equatable, Sendable {
    public var sessionId: UUID
    public var status: SyncStatus
    public var publicKeyBase64: String?
    public var accepted: Bool
    public var errorMessage: String?

    public init(
        sessionId: UUID,
        status: SyncStatus = .ready,
        publicKeyBase64: String? = nil,
        accepted: Bool = true,
        errorMessage: String? = nil
    ) {
        self.sessionId = sessionId
        self.status = status
        self.publicKeyBase64 = publicKeyBase64
        self.accepted = accepted
        self.errorMessage = errorMessage
    }
}
