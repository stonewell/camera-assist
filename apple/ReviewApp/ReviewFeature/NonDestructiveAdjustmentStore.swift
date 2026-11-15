import Foundation

#if canImport(Photos)
import Photos
#endif

// MARK: - Adjustment Payload

/// Non-destructive photo transformation parameters serialized into PhotoKit adjustment sidecars.
public struct AdjustmentPayload: Codable, Sendable, Equatable {
    public static let currentFormatIdentifier = "com.cameraassist.adjustment"
    public static let currentFormatVersion = "1.0"

    public var formatIdentifier: String
    public var formatVersion: String
    public var straightenAngleDeg: Double?
    public var cropX: Double?
    public var cropY: Double?
    public var cropWidth: Double?
    public var cropHeight: Double?
    public var timestamp: Date

    public init(
        straightenAngleDeg: Double? = nil,
        cropX: Double? = nil,
        cropY: Double? = nil,
        cropWidth: Double? = nil,
        cropHeight: Double? = nil,
        timestamp: Date = Date()
    ) {
        self.formatIdentifier = Self.currentFormatIdentifier
        self.formatVersion = Self.currentFormatVersion
        self.straightenAngleDeg = straightenAngleDeg
        self.cropX = cropX
        self.cropY = cropY
        self.cropWidth = cropWidth
        self.cropHeight = cropHeight
        self.timestamp = timestamp
    }

    public func toJSONData() -> Data? {
        try? JSONEncoder().encode(self)
    }

    public static func fromJSONData(_ data: Data) -> AdjustmentPayload? {
        try? JSONDecoder().decode(AdjustmentPayload.self, from: data)
    }

    #if canImport(Photos)
    /// Converts payload into Apple PhotoKit PHAdjustmentData for non-destructive library persistence.
    public func toPHAdjustmentData() -> PHAdjustmentData? {
        guard let data = toJSONData() else { return nil }
        return PHAdjustmentData(
            formatIdentifier: formatIdentifier,
            formatVersion: formatVersion,
            data: data
        )
    }

    /// Reads back payload from Apple PhotoKit PHAdjustmentData.
    public static func fromPHAdjustmentData(_ adjustmentData: PHAdjustmentData) -> AdjustmentPayload? {
        guard adjustmentData.formatIdentifier == currentFormatIdentifier else { return nil }
        return fromJSONData(adjustmentData.data)
    }
    #endif
}

// MARK: - Non-Destructive Adjustment Store

/// In-memory and PhotoKit-backed store managing non-destructive straighten and crop adjustments.
public final class NonDestructiveAdjustmentStore: @unchecked Sendable {
    public static let shared = NonDestructiveAdjustmentStore()

    private let lock = NSLock()
    private var adjustments: [String: AdjustmentPayload] = [:]

    public init() {}

    /// Persists non-destructive adjustment for a photo identifier.
    public func saveAdjustment(for photoId: String, payload: AdjustmentPayload) {
        lock.lock()
        defer { lock.unlock() }
        adjustments[photoId] = payload
    }

    /// Retrieves active adjustment payload for a photo identifier if present.
    public func getAdjustment(for photoId: String) -> AdjustmentPayload? {
        lock.lock()
        defer { lock.unlock() }
        return adjustments[photoId]
    }

    /// Reverts and removes any non-destructive adjustment for a photo identifier.
    public func revertAdjustment(for photoId: String) {
        lock.lock()
        defer { lock.unlock() }
        adjustments.removeValue(forKey: photoId)
    }

    /// Returns whether a photo has an active non-destructive adjustment applied.
    public func hasAdjustment(for photoId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return adjustments[photoId] != nil
    }

    /// Clears all cached adjustments.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        adjustments.removeAll()
    }
}
