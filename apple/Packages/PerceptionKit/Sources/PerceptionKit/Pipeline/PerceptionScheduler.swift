import Foundation
import CoreGraphics

#if canImport(CoreVideo)
import CoreVideo
#endif

/// Multi-rate perception task schedule decision for a given frame timestamp.
public struct ScheduledPerceptionTasks: Sendable, Equatable {
    public let runBodyPose: Bool
    public let runSegmentationMask: Bool
    public let runFaceFallback: Bool
    public let runLumaProbe: Bool

    public init(
        runBodyPose: Bool,
        runSegmentationMask: Bool,
        runFaceFallback: Bool,
        runLumaProbe: Bool
    ) {
        self.runBodyPose = runBodyPose
        self.runSegmentationMask = runSegmentationMask
        self.runFaceFallback = runFaceFallback
        self.runLumaProbe = runLumaProbe
    }
}

/// Multi-rate scheduler governing Vision inference cadences (15Hz pose, 8Hz mask, 10Hz face, 4Hz luma)
/// with automatic thermal-state throttling and Y-plane backlight luma probing.
public final class PerceptionScheduler: @unchecked Sendable {
    private var lastPoseTime: Double = -.infinity
    private var lastMaskTime: Double = -.infinity
    private var lastFaceTime: Double = -.infinity
    private var lastLumaTime: Double = -.infinity

    public var basePoseHz: Double = 15.0
    public var baseMaskHz: Double = 8.0
    public var baseFaceHz: Double = 10.0
    public var baseLumaHz: Double = 4.0

    public init() {}

    /// Evaluates which perception tasks should execute at `timestamp` given the current thermal state.
    public func schedule(
        at timestamp: Double,
        thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState,
        lastPoseHadSubject: Bool = true
    ) -> ScheduledPerceptionTasks {
        let rateMultiplier: Double
        let allowMask: Bool

        switch thermalState {
        case .nominal, .fair:
            rateMultiplier = 1.0
            allowMask = true
        case .serious:
            rateMultiplier = 0.5
            allowMask = true
        case .critical:
            rateMultiplier = 0.25
            allowMask = false
        @unknown default:
            rateMultiplier = 1.0
            allowMask = true
        }

        let poseInterval = 1.0 / (basePoseHz * rateMultiplier)
        let maskInterval = 1.0 / (baseMaskHz * rateMultiplier)
        let faceInterval = 1.0 / (baseFaceHz * rateMultiplier)
        let lumaInterval = 1.0 / (baseLumaHz * rateMultiplier)

        let runPose = (timestamp - lastPoseTime) >= poseInterval
        if runPose { lastPoseTime = timestamp }

        let runMask = allowMask && (timestamp - lastMaskTime) >= maskInterval
        if runMask { lastMaskTime = timestamp }

        let runFace = !lastPoseHadSubject && (timestamp - lastFaceTime) >= faceInterval
        if runFace { lastFaceTime = timestamp }

        let runLuma = (timestamp - lastLumaTime) >= lumaInterval
        if runLuma { lastLumaTime = timestamp }

        return ScheduledPerceptionTasks(
            runBodyPose: runPose,
            runSegmentationMask: runMask,
            runFaceFallback: runFace,
            runLumaProbe: runLuma
        )
    }

    /// Computes face-to-background luminance ratio from an 8-bit luma grid (e.g. Y-plane of `420v`)
    /// to detect severe backlight conditions (`faceToBgRatio < 0.45`).
    public static func computeFaceToBackgroundRatio(
        lumaGrid: [UInt8],
        width: Int,
        height: Int,
        subjectBox: NormalizedBox
    ) -> Float {
        guard width > 0, height > 0, lumaGrid.count >= width * height else { return 1.0 }

        var subjSum: Double = 0.0
        var subjCount: Int = 0
        var bgSum: Double = 0.0
        var bgCount: Int = 0

        let minC = max(0, Int(subjectBox.min_x * Float(width)))
        let maxC = min(width - 1, Int(subjectBox.max_x * Float(width)))
        let minR = max(0, Int(subjectBox.min_y * Float(height)))
        let maxR = min(height - 1, Int((subjectBox.min_y + subjectBox.height * 0.35) * Float(height)))

        for r in 0..<height {
            let rowOffset = r * width
            for c in 0..<width {
                let val = Double(lumaGrid[rowOffset + c])
                if r >= minR && r <= maxR && c >= minC && c <= maxC {
                    subjSum += val
                    subjCount += 1
                } else {
                    bgSum += val
                    bgCount += 1
                }
            }
        }

        guard subjCount > 0, bgCount > 0 else { return 1.0 }
        let subjMean = subjSum / Double(subjCount)
        let bgMean = max(1.0, bgSum / Double(bgCount))
        return Float(subjMean / bgMean)
    }

    public func reset() {
        lastPoseTime = -.infinity
        lastMaskTime = -.infinity
        lastFaceTime = -.infinity
        lastLumaTime = -.infinity
    }
}
