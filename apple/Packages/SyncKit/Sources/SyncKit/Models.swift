import Foundation

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
}

/// Session status for App Clip stranger assist mode.
public enum SyncStatus: String, Codable, Sendable {
    case pending = "pending"
    case captured = "captured"
    case syncing = "syncing"
    case completed = "completed"
    case expired = "expired"
}

/// End-to-end encrypted envelope for transport over relay / AirDrop / CloudKit.
public struct EncryptionEnvelope: Codable, Equatable, Sendable {
    public var keyId: String
    public var nonceBase64: String
    public var ciphertext: Data
    public var tagBase64: String

    public init(keyId: String, nonceBase64: String, ciphertext: Data, tagBase64: String) {
        self.keyId = keyId
        self.nonceBase64 = nonceBase64
        self.ciphertext = ciphertext
        self.tagBase64 = tagBase64
    }
}

/// Reference visual package sent by owner device to App Clip guest device.
public struct ReferencePackage: Codable, Equatable, Sendable {
    public var sessionId: UUID
    public var ownerDeviceToken: String
    public var promptKey: String
    public var targetFraming: NormalizedRect
    public var compositionType: String
    public var previewThumbnailData: Data?
    public var createdTimestamp: Double
    public var expiresTimestamp: Double

    public init(
        sessionId: UUID = UUID(),
        ownerDeviceToken: String,
        promptKey: String,
        targetFraming: NormalizedRect,
        compositionType: String,
        previewThumbnailData: Data? = nil,
        createdTimestamp: Double = Date().timeIntervalSince1970,
        expiresTimestamp: Double = Date().timeIntervalSince1970 + 600.0 // 10 minutes default TTL
    ) {
        self.sessionId = sessionId
        self.ownerDeviceToken = ownerDeviceToken
        self.promptKey = promptKey
        self.targetFraming = targetFraming
        self.compositionType = compositionType
        self.previewThumbnailData = previewThumbnailData
        self.createdTimestamp = createdTimestamp
        self.expiresTimestamp = expiresTimestamp
    }

    public var isExpired: Bool {
        Date().timeIntervalSince1970 > expiresTimestamp
    }
}

/// Photographic capture package produced by App Clip guest camera, returned to owner.
public struct CapturePackage: Codable, Equatable, Sendable {
    public var sessionId: UUID
    public var capturedPhotoJpeg: Data
    public var cameraPitch: Float
    public var cameraRoll: Float
    public var focalLengthMm: Float
    public var capturedTimestamp: Double
    public var clientNonce: String

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
        self.capturedPhotoJpeg = capturedPhotoJpeg
        self.cameraPitch = cameraPitch
        self.cameraRoll = cameraRoll
        self.focalLengthMm = focalLengthMm
        self.capturedTimestamp = capturedTimestamp
        self.clientNonce = clientNonce
    }
}
