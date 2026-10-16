import Foundation
import CoreGraphics

/// Subject selection, spatial scoring, stickiness tracking, and multi-person group merging.
public final class SubjectTracker: @unchecked Sendable {
    private var lastPrimaryBbox: NormalizedBox?
    public var trackingThresholdIoU: Float = 0.3
    public var groupMergeAreaRatioLimit: Float = 1.5

    public init() {}

    /// Compute Intersection over Union (IoU) between two normalized bounding boxes.
    public static func computeIoU(_ a: NormalizedBox, _ b: NormalizedBox) -> Float {
        let interMinX = max(a.min_x, b.min_x)
        let interMinY = max(a.min_y, b.min_y)
        let interMaxX = min(a.max_x, b.max_x)
        let interMaxY = min(a.max_y, b.max_y)

        let interW = max(0.0, interMaxX - interMinX)
        let interH = max(0.0, interMaxY - interMinY)
        let interArea = interW * interH

        let areaA = max(0.0, a.max_x - a.min_x) * max(0.0, a.max_y - a.min_y)
        let areaB = max(0.0, b.max_x - b.min_x) * max(0.0, b.max_y - b.min_y)
        let unionArea = areaA + areaB - interArea

        guard unionArea > 0.0001 else { return 0.0 }
        return interArea / unionArea
    }

    /// Compute spatial score for a candidate subject.
    private func computeScore(bbox: NormalizedBox) -> Float {
        let width = max(0.0, bbox.max_x - bbox.min_x)
        let height = max(0.0, bbox.max_y - bbox.min_y)
        let area = width * height

        let centerX = (bbox.min_x + bbox.max_x) / 2.0
        let centerY = (bbox.min_y + bbox.max_y) / 2.0
        let dx = centerX - 0.5
        let dy = centerY - 0.5
        let dist = sqrt(dx * dx + dy * dy)

        var score = area * (1.0 - 0.5 * dist)

        // Apply tracking stickiness if close to last selected primary subject
        if let last = lastPrimaryBbox {
            let iou = Self.computeIoU(bbox, last)
            if iou >= trackingThresholdIoU {
                score *= 1.5
            }
        }
        return score
    }

    /// Track, score, and optionally group merge subjects for the current frame.
    public func track(subjects: [Subject]) -> [Subject] {
        guard !subjects.isEmpty else {
            lastPrimaryBbox = nil
            return []
        }

        // Rank candidates by spatial score
        var scored = subjects.map { (subject: $0, score: computeScore(bbox: $0.bbox)) }
        scored.sort { $0.score > $1.score }

        var result = scored.map { $0.subject }

        // Check group merging if 2 balanced subjects are present
        if result.count == 2 {
            let s1 = result[0]
            let s2 = result[1]
            let area1 = (s1.bbox.max_x - s1.bbox.min_x) * (s1.bbox.max_y - s1.bbox.min_y)
            let area2 = (s2.bbox.max_x - s2.bbox.min_x) * (s2.bbox.max_y - s2.bbox.min_y)

            let minArea = min(area1, area2)
            let maxArea = max(area1, area2)

            if minArea > 0.01 && (maxArea / minArea) < groupMergeAreaRatioLimit {
                // Merge into a group subject
                let unionBox = NormalizedBox(
                    min_x: min(s1.bbox.min_x, s2.bbox.min_x),
                    min_y: min(s1.bbox.min_y, s2.bbox.min_y),
                    max_x: max(s1.bbox.max_x, s2.bbox.max_x),
                    max_y: max(s1.bbox.max_y, s2.bbox.max_y)
                )

                let groupSubject = Subject(
                    id: "group_merged",
                    bbox: unionBox,
                    joints: s1.joints, // Primary joints
                    shot_type: "FullBody",
                    facing: "Front",
                    is_group: true,
                    mask: MaskSummarizer.summarize(bbox: unionBox)
                )

                result = [groupSubject, s1, s2]
            }
        }

        if let primary = result.first {
            lastPrimaryBbox = primary.bbox
        }

        return result
    }

    /// Reset tracker memory.
    public func reset() {
        lastPrimaryBbox = nil
    }
}
