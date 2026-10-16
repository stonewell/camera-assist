import Foundation
import CoreGraphics

#if canImport(Vision)
import Vision
#endif

/// Analyzes body poses, extracts 17 standard skeletal keypoints,
/// normalizes coordinates to top-left origin, and applies One Euro temporal smoothing.
public final class BodyPoseAnalyzer: @unchecked Sendable {
    private var jointFilters: [String: (xFilter: OneEuroFilter, yFilter: OneEuroFilter, missedFrames: Int)] = [:]
    public var minConfidence: Float = 0.3

    public init(minConfidence: Float = 0.3) {
        self.minConfidence = minConfidence
    }

    /// Convert raw keypoint dictionaries (e.g. from VNDetectHumanBodyPoseRequest or Mock)
    /// into normalized, smoothed joints.
    public func processKeypoints(
        _ rawJoints: [String: (point: CGPoint, confidence: Float)],
        timestamp: Double
    ) -> [String: Joint] {
        var processed: [String: Joint] = [:]

        for (jointName, data) in rawJoints {
            guard data.confidence >= minConfidence else {
                // Increment missed counter
                if var entry = jointFilters[jointName] {
                    entry.missedFrames += 1
                    if entry.missedFrames >= 3 {
                        entry.xFilter.reset()
                        entry.yFilter.reset()
                    }
                    jointFilters[jointName] = entry
                }
                continue
            }

            // Normalization: invert Y axis from Vision bottom-left to top-left
            let normX = Double(data.point.x)
            let normY = Double(1.0 - data.point.y)

            var entry = jointFilters[jointName] ?? (OneEuroFilter(), OneEuroFilter(), 0)
            entry.missedFrames = 0

            let smoothedX = entry.xFilter.filter(normX, timestamp: timestamp)
            let smoothedY = entry.yFilter.filter(normY, timestamp: timestamp)
            jointFilters[jointName] = entry

            processed[jointName] = Joint(
                x: Float(max(0.0, min(1.0, smoothedX))),
                y: Float(max(0.0, min(1.0, smoothedY))),
                confidence: data.confidence
            )
        }

        return processed
    }

    /// Reset all smoothing filters (e.g. on scene cut or subject switch).
    public func reset() {
        jointFilters.removeAll()
    }
}
