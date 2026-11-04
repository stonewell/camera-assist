import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
#endif

#if canImport(ImageIO)
import ImageIO
#endif

#if canImport(AVFoundation)
import AVFoundation
#endif

#if canImport(QuartzCore)
import QuartzCore
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
/// match the user's perceptual orientation via real KVO observations.
public final class RotationCoordinatorBridge: @unchecked Sendable {
    public typealias AngleChangeHandler = @Sendable (RotationAngles) -> Void

    private let lock = NSLock()
    private var _currentAngles: RotationAngles
    private var _onAnglesChanged: AngleChangeHandler?

    #if canImport(AVFoundation)
    private var coordinator: AnyObject?
    private var previewObservation: NSKeyValueObservation?
    private var captureObservation: NSKeyValueObservation?
    #endif

    public var currentAngles: RotationAngles {
        lock.lock()
        defer { lock.unlock() }
        return _currentAngles
    }

    public var onAnglesChanged: AngleChangeHandler? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _onAnglesChanged
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _onAnglesChanged = newValue
        }
    }

    public init(initialAngles: RotationAngles = .portrait, onAnglesChanged: AngleChangeHandler? = nil) {
        self._currentAngles = initialAngles
        self._onAnglesChanged = onAnglesChanged
    }

    /// Update angles dynamically (e.g. from KVO observation on iOS 17+ RotationCoordinator).
    public func update(previewAngle: CGFloat, captureAngle: CGFloat) {
        let angles = RotationAngles(previewAngleDeg: previewAngle, captureAngleDeg: captureAngle)
        let handler: AngleChangeHandler?
        lock.lock()
        self._currentAngles = angles
        handler = self._onAnglesChanged
        lock.unlock()
        handler?(angles)
    }

    /// Maps capture rotation angle to CGImagePropertyOrientation required by Vision framework.
    public var visionOrientation: CGImagePropertyOrientation {
        VisionOrientationMapper.visionOrientation(captureAngle: currentAngles.captureAngleDeg)
    }

    #if canImport(AVFoundation)
    /// Observes real-time rotation changes using AVCaptureDevice.RotationCoordinator on iOS 17+.
    @available(iOS 17.0, macOS 14.0, *)
    public func observe(device: AVCaptureDevice, previewLayer: CALayer? = nil) {
        stopObserving()

        let coord = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)

        lock.lock()
        self.coordinator = coord
        lock.unlock()

        // Sync initial orientation angles
        update(
            previewAngle: coord.videoRotationAngleForHorizonLevelPreview,
            captureAngle: coord.videoRotationAngleForHorizonLevelCapture
        )

        // Real KVO on preview horizon-level angle
        self.previewObservation = coord.observe(
            \.videoRotationAngleForHorizonLevelPreview,
            options: [.new]
        ) { [weak self] observedCoord, _ in
            guard let self = self else { return }
            self.update(
                previewAngle: observedCoord.videoRotationAngleForHorizonLevelPreview,
                captureAngle: observedCoord.videoRotationAngleForHorizonLevelCapture
            )
        }

        // Real KVO on capture horizon-level angle
        self.captureObservation = coord.observe(
            \.videoRotationAngleForHorizonLevelCapture,
            options: [.new]
        ) { [weak self] observedCoord, _ in
            guard let self = self else { return }
            self.update(
                previewAngle: observedCoord.videoRotationAngleForHorizonLevelPreview,
                captureAngle: observedCoord.videoRotationAngleForHorizonLevelCapture
            )
        }
    }

    /// Check if active KVO observation is established.
    public var isObserving: Bool {
        lock.lock()
        defer { lock.unlock() }
        return coordinator != nil
    }

    /// Stop KVO observations and invalidate tokens.
    public func stopObserving() {
        lock.lock()
        previewObservation?.invalidate()
        previewObservation = nil
        captureObservation?.invalidate()
        captureObservation = nil
        coordinator = nil
        lock.unlock()
    }
    #else
    public var isObserving: Bool { false }
    public func stopObserving() {}
    #endif

    deinit {
        stopObserving()
    }
}
