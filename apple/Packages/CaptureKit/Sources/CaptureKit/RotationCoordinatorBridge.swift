import Foundation
import CoreGraphics

#if canImport(ImageIO)
import ImageIO
#endif

/// Orientation coordinates and rotation angles for preview and still photo capture.
public struct RotationAngles: Sendable, Equatable {
    public let previewAngleDeg: CGFloat
    public let captureAngleDeg: CGFloat

    public init(previewAngleDeg: CGFloat = 90.0, captureAngleDeg: CGFloat = 90.0) {
        self.previewAngleDeg = previewAngleDeg
        self.captureAngleDeg = captureAngleDeg
    }

    /// Standard upright portrait orientation (home indicator / charging port at bottom).
    public static let portrait = RotationAngles(previewAngleDeg: 90.0, captureAngleDeg: 90.0)

    /// Landscape orientation with phone turned 90 degrees counter-clockwise.
    public static let landscapeLeft = RotationAngles(previewAngleDeg: 0.0, captureAngleDeg: 0.0)

    /// Landscape orientation with phone turned 90 degrees clockwise.
    public static let landscapeRight = RotationAngles(previewAngleDeg: 180.0, captureAngleDeg: 180.0)

    /// Inverted portrait orientation.
    public static let portraitUpsideDown = RotationAngles(previewAngleDeg: 270.0, captureAngleDeg: 270.0)
}

/// Bridge for iOS 17+ AVCaptureDevice.RotationCoordinator.
/// Maintains horizon-level video rotation angles and ensures camera sensor coordinates
/// match the user's perceptual orientation.
public final class RotationCoordinatorBridge: @unchecked Sendable {
    public private(set) var currentAngles: RotationAngles

    public init(initialAngles: RotationAngles = .portrait) {
        self.currentAngles = initialAngles
    }

    /// Update angles dynamically (e.g. from KVO observation on iOS 17+ RotationCoordinator).
    public func update(previewAngle: CGFloat, captureAngle: CGFloat) {
        self.currentAngles = RotationAngles(previewAngleDeg: previewAngle, captureAngleDeg: captureAngle)
    }

    /// Maps capture rotation angle to CGImagePropertyOrientation required by Vision framework.
    public var visionOrientation: CGImagePropertyOrientation {
        VisionOrientationMapper.visionOrientation(captureAngle: currentAngles.captureAngleDeg)
    }
}
