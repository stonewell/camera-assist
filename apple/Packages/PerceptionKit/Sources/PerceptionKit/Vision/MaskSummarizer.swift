import Foundation
import CoreGraphics

/// Evaluates instance segmentation mask metrics to determine headroom, boundaries, and crops.
public enum MaskSummarizer {
    /// Compute MaskSummary from normalized mask coordinates or bounding box.
    public static func summarize(
        bbox: NormalizedBox,
        topY: Float? = nil,
        edgeMargin: Float = 0.015
    ) -> MaskSummary {
        let actualTopY = topY ?? bbox.min_y
        let touchesTop = actualTopY <= edgeMargin
        let touchesBottom = bbox.max_y >= (1.0 - edgeMargin)
        let touchesLeft = bbox.min_x <= edgeMargin
        let touchesRight = bbox.max_x >= (1.0 - edgeMargin)

        return MaskSummary(
            top_y: actualTopY,
            touches_top: touchesTop,
            touches_bottom: touchesBottom,
            touches_left: touchesLeft,
            touches_right: touchesRight
        )
    }
}
