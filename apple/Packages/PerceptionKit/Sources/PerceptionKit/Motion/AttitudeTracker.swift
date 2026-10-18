import Foundation
import CoreGraphics

#if canImport(CoreMotion) && !os(macOS)
import CoreMotion
#endif

/// Device motion measurement at an instant in time.
public struct MotionReading: Sendable, Equatable {
    public let timestamp: Double
    public let gravityX: Double
    public let gravityY: Double
    public let gravityZ: Double
    public let rotationRateX: Double
    public let rotationRateY: Double
    public let rotationRateZ: Double

    public init(
        timestamp: Double = CFAbsoluteTimeGetCurrent(),
        gravityX: Double = 0.0,
        gravityY: Double = -1.0, // Default: upright gravity pointing down along -Y
        gravityZ: Double = 0.0,
        rotationRateX: Double = 0.0,
        rotationRateY: Double = 0.0,
        rotationRateZ: Double = 0.0
    ) {
        self.timestamp = timestamp
        self.gravityX = gravityX
        self.gravityY = gravityY
        self.gravityZ = gravityZ
        self.rotationRateX = rotationRateX
        self.rotationRateY = rotationRateY
        self.rotationRateZ = rotationRateZ
    }

    /// Upright stationary phone.
    public static let uprightStill = MotionReading(
        timestamp: 0.0,
        gravityX: 0.0,
        gravityY: -1.0,
        gravityZ: 0.0
    )

    /// Magnitude of angular rotation speed in rad/s.
    public var angularSpeed: Double {
        sqrt(rotationRateX * rotationRateX + rotationRateY * rotationRateY + rotationRateZ * rotationRateZ)
    }
}

/// Computes filtered camera roll, pitch, elevation, angular speed, and flat-orientation state from 60Hz IMU gravity vector.
public final class AttitudeTracker: @unchecked Sendable {
    private let rollFilter: OneEuroFilter
    private let pitchFilter: OneEuroFilter
    public var captureAngleDeg: CGFloat = 90.0

    #if canImport(CoreMotion) && !os(macOS)
    private let motionManager = CMMotionManager()
    private let motionQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.cameraassist.perceptionkit.motion"
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInteractive
        return q
    }()
    #endif

    public init(minCutoff: Double = 1.0, beta: Double = 0.01, dCutoff: Double = 1.0) {
        self.rollFilter = OneEuroFilter(minCutoff: minCutoff, beta: beta, dCutoff: dCutoff)
        self.pitchFilter = OneEuroFilter(minCutoff: minCutoff, beta: beta, dCutoff: dCutoff)
    }

    /// Process a 60Hz motion reading and return filtered Posture.
    public func process(reading: MotionReading) -> Posture {
        let gx = reading.gravityX
        let gy = reading.gravityY
        let gz = max(-1.0, min(1.0, reading.gravityZ))

        // Elevation angle: lens facing upward vs downward
        let rawPitch = asin(gz) * 180.0 / .pi

        // Roll angle relative to active capture orientation
        let rawRoll: Double
        switch Int(captureAngleDeg) {
        case 90:
            rawRoll = atan2(gx, -gy) * 180.0 / .pi
        case 270:
            rawRoll = atan2(-gx, gy) * 180.0 / .pi
        case 0:
            rawRoll = atan2(-gy, -gx) * 180.0 / .pi
        default:
            rawRoll = atan2(gy, gx) * 180.0 / .pi
        }

        let filteredRoll = rollFilter.filter(rawRoll, timestamp: reading.timestamp)
        let filteredPitch = pitchFilter.filter(rawPitch, timestamp: reading.timestamp)
        let isFlatish = abs(gz) > 0.85

        return Posture(
            roll_deg: Float(filteredRoll),
            pitch_deg: Float(filteredPitch),
            elevation_deg: Float(filteredPitch),
            angular_speed: Float(reading.angularSpeed),
            is_flatish: isFlatish
        )
    }

    #if canImport(CoreMotion) && !os(macOS)
    /// Starts live 60Hz CoreMotion device-motion updates and invokes `onReading` on the motion queue.
    public func startLiveMotionUpdates(onReading: @escaping @Sendable (MotionReading) -> Void) {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: motionQueue) { motion, _ in
            guard let motion = motion else { return }
            let reading = MotionReading(
                timestamp: motion.timestamp,
                gravityX: motion.gravity.x,
                gravityY: motion.gravity.y,
                gravityZ: motion.gravity.z,
                rotationRateX: motion.rotationRate.x,
                rotationRateY: motion.rotationRate.y,
                rotationRateZ: motion.rotationRate.z
            )
            onReading(reading)
        }
    }

    /// Stops live CoreMotion device-motion updates.
    public func stopLiveMotionUpdates() {
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
    }
    #endif

    /// Reset internal filter state.
    public func reset() {
        rollFilter.reset()
        pitchFilter.reset()
    }
}
