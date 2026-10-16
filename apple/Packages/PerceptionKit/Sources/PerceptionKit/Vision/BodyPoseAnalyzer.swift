import Foundation
import CoreGraphics

#if canImport(Vision)
import Vision
#endif
#if canImport(CoreVideo)
import CoreVideo
#endif
#if canImport(ImageIO)
import ImageIO
#endif

/// Analyzes body poses, extracts 19 canonical skeletal keypoints (17 COCO + Neck + Root),
/// normalizes coordinates to top-left origin, and applies One Euro temporal smoothing.
public final class BodyPoseAnalyzer: @unchecked Sendable {
    private var jointFilters: [String: (xFilter: OneEuroFilter, yFilter: OneEuroFilter, missedFrames: Int)] = [:]
    public var minConfidence: Float = 0.3

    public init(minConfidence: Float = 0.3) {
        self.minConfidence = minConfidence
    }

    /// Convert raw keypoint dictionaries (e.g. from VNDetectHumanBodyPoseRequest or Mock)
    /// into normalized, smoothed joints with canonical PascalCase `JointType` keys.
    public func processKeypoints(
        _ rawJoints: [String: (point: CGPoint, confidence: Float)],
        timestamp: Double
    ) -> [String: Joint] {
        var processed: [String: Joint] = [:]

        for (rawKey, data) in rawJoints {
            let jointType = JointType.from(key: rawKey) ?? .Nose
            let canonicalKey = jointType.rawValue

            guard data.confidence >= minConfidence else {
                if var entry = jointFilters[canonicalKey] {
                    entry.missedFrames += 1
                    if entry.missedFrames >= 3 {
                        entry.xFilter.reset()
                        entry.yFilter.reset()
                    }
                    jointFilters[canonicalKey] = entry
                }
                continue
            }

            // Normalization: invert Y axis from Vision bottom-left to top-left
            let normX = Double(data.point.x)
            let normY = Double(1.0 - data.point.y)

            var entry = jointFilters[canonicalKey] ?? (OneEuroFilter(), OneEuroFilter(), 0)
            entry.missedFrames = 0

            let smoothedX = entry.xFilter.filter(normX, timestamp: timestamp)
            let smoothedY = entry.yFilter.filter(normY, timestamp: timestamp)
            jointFilters[canonicalKey] = entry

            let joint = Joint(
                joint_type: jointType,
                x: Float(max(0.0, min(1.0, smoothedX))),
                y: Float(max(0.0, min(1.0, smoothedY))),
                confidence: data.confidence
            )
            processed[canonicalKey] = joint
            if rawKey != canonicalKey {
                processed[rawKey] = joint
            }
        }

        // Synthesize Neck and Root if missing and shoulders/hips are available
        if processed[JointType.Neck.rawValue] == nil,
           let ls = processed[JointType.LeftShoulder.rawValue],
           let rs = processed[JointType.RightShoulder.rawValue] {
            let neck = Joint(
                joint_type: .Neck,
                x: (ls.x + rs.x) * 0.5,
                y: (ls.y + rs.y) * 0.5,
                confidence: min(ls.confidence, rs.confidence)
            )
            processed[JointType.Neck.rawValue] = neck
        }

        if processed[JointType.Root.rawValue] == nil,
           let lh = processed[JointType.LeftHip.rawValue],
           let rh = processed[JointType.RightHip.rawValue] {
            let root = Joint(
                joint_type: .Root,
                x: (lh.x + rh.x) * 0.5,
                y: (lh.y + rh.y) * 0.5,
                confidence: min(lh.confidence, rh.confidence)
            )
            processed[JointType.Root.rawValue] = root
        }

        return processed
    }

    #if canImport(Vision) && canImport(CoreVideo) && canImport(ImageIO)
    /// Runs `VNDetectHumanBodyPoseRequest` (and `VNDetectFaceRectanglesRequest` fallback) on a live pixel buffer.
    public func analyzePixelBuffer(
        _ pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation = .right,
        timestamp: Double
    ) throws -> [Subject] {
        let poseRequest = VNDetectHumanBodyPoseRequest()
        let faceRequest = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        try handler.perform([poseRequest, faceRequest])

        var subjects: [Subject] = []
        if let observations = poseRequest.results, !observations.isEmpty {
            for (idx, obs) in observations.enumerated() {
                let recognized = (try? obs.recognizedPoints(.all)) ?? [:]
                var rawMap: [String: (point: CGPoint, confidence: Float)] = [:]
                var minX: Float = 1.0
                var minY: Float = 1.0
                var maxX: Float = 0.0
                var maxY: Float = 0.0

                for (key, pt) in recognized where pt.confidence >= minConfidence {
                    rawMap[key.rawValue.rawValue] = (point: pt.location, confidence: pt.confidence)
                    let nx = Float(pt.location.x)
                    let ny = Float(1.0 - pt.location.y)
                    minX = min(minX, nx)
                    minY = min(minY, ny)
                    maxX = max(maxX, nx)
                    maxY = max(maxY, ny)
                }

                let joints = processKeypoints(rawMap, timestamp: timestamp)
                guard !joints.isEmpty else { continue }

                let padX = max(0.04, (maxX - minX) * 0.15)
                let padY = max(0.05, (maxY - minY) * 0.12)
                let bounds = NormalizedBox(
                    min_x: max(0.0, minX - padX),
                    min_y: max(0.0, minY - padY),
                    max_x: min(1.0, maxX + padX),
                    max_y: min(1.0, maxY + padY)
                )

                subjects.append(
                    Subject(
                        id: UInt32(idx + 1),
                        bounds: bounds,
                        joints: joints,
                        facing: "Frontal",
                        shot_type: "Unknown",
                        confidence: obs.confidence
                    )
                )
            }
        } else if let faces = faceRequest.results, !faces.isEmpty {
            for (idx, face) in faces.enumerated() {
                let bb = face.boundingBox
                let topY = Float(1.0 - bb.maxY)
                let bottomY = min(1.0, Float(1.0 - bb.minY) + Float(bb.height * 2.5))
                let bounds = NormalizedBox(
                    min_x: max(0.0, Float(bb.minX - bb.width * 0.5)),
                    min_y: max(0.0, topY),
                    max_x: min(1.0, Float(bb.maxX + bb.width * 0.5)),
                    max_y: bottomY
                )
                subjects.append(
                    Subject(
                        id: UInt32(idx + 1),
                        bounds: bounds,
                        joints: [:],
                        facing: "Frontal",
                        shot_type: "CloseUp",
                        confidence: face.confidence
                    )
                )
            }
        }

        return subjects
    }
    #endif

    /// Reset all smoothing filters (e.g. on scene cut or subject switch).
    public func reset() {
        jointFilters.removeAll()
    }
}
