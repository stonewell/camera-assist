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

/// Evaluates instance segmentation mask metrics (128x96 downsampled grid or bounding box fallback)
/// to determine headroom, horizontal zone spans (`head_cols`, `torso_cols`, `leg_cols`), and edge contacts.
public enum MaskSummarizer {
    /// Compute MaskSummary from normalized mask coordinates or bounding box fallback.
    public static func summarize(
        bbox: NormalizedBox,
        topY: Float? = nil,
        bottomY: Float? = nil,
        edgeMargin: Float = 0.015
    ) -> MaskSummary {
        let actualTopY = topY ?? bbox.min_y
        let actualBottomY = bottomY ?? bbox.max_y
        let cols: [Float] = [bbox.min_x, bbox.max_x]
        let touchesTop = actualTopY <= edgeMargin
        let touchesBottom = actualBottomY >= (1.0 - edgeMargin)
        let touchesLeft = bbox.min_x <= edgeMargin
        let touchesRight = bbox.max_x >= (1.0 - edgeMargin)

        return MaskSummary(
            top_y: actualTopY,
            bottom_y: actualBottomY,
            head_cols: cols,
            torso_cols: cols,
            leg_cols: cols,
            touches_top: touchesTop,
            touches_bottom: touchesBottom,
            touches_left: touchesLeft,
            touches_right: touchesRight
        )
    }

    /// Scans a downsampled 8-bit segmentation grid (e.g., 128x96) and computes `MaskSummary`
    /// including `top_y`, `bottom_y`, and horizontal column spans for head, torso, and leg bands.
    public static func summarizeMaskGrid(
        grid: [UInt8],
        width: Int,
        height: Int,
        threshold: UInt8 = 128,
        edgeMargin: Float = 0.015
    ) -> MaskSummary? {
        guard width > 0, height > 0, grid.count >= width * height else { return nil }

        var minRow = height
        var maxRow = -1
        var minCol = width
        var maxCol = -1

        let headEndRow = max(1, height / 4)
        let torsoEndRow = max(headEndRow + 1, (height * 3) / 4)

        var headMinC = width, headMaxC = -1
        var torsoMinC = width, torsoMaxC = -1
        var legMinC = width, legMaxC = -1

        for r in 0..<height {
            let rowOffset = r * width
            for c in 0..<width {
                if grid[rowOffset + c] >= threshold {
                    if r < minRow { minRow = r }
                    if r > maxRow { maxRow = r }
                    if c < minCol { minCol = c }
                    if c > maxCol { maxCol = c }

                    if r < headEndRow {
                        if c < headMinC { headMinC = c }
                        if c > headMaxC { headMaxC = c }
                    } else if r < torsoEndRow {
                        if c < torsoMinC { torsoMinC = c }
                        if c > torsoMaxC { torsoMaxC = c }
                    } else {
                        if c < legMinC { legMinC = c }
                        if c > legMaxC { legMaxC = c }
                    }
                }
            }
        }

        guard maxRow >= minRow else { return nil }

        let invW = 1.0 / Float(max(1, width - 1))
        let invH = 1.0 / Float(max(1, height - 1))

        let topY = Float(minRow) * invH
        let bottomY = Float(maxRow) * invH
        let leftX = Float(minCol) * invW
        let rightX = Float(maxCol) * invW

        let headCols: [Float] = headMaxC >= headMinC
            ? [Float(headMinC) * invW, Float(headMaxC) * invW]
            : [leftX, rightX]
        let torsoCols: [Float] = torsoMaxC >= torsoMinC
            ? [Float(torsoMinC) * invW, Float(torsoMaxC) * invW]
            : [leftX, rightX]
        let legCols: [Float] = legMaxC >= legMinC
            ? [Float(legMinC) * invW, Float(legMaxC) * invW]
            : [leftX, rightX]

        return MaskSummary(
            top_y: topY,
            bottom_y: bottomY,
            head_cols: headCols,
            torso_cols: torsoCols,
            leg_cols: legCols,
            touches_top: topY <= edgeMargin,
            touches_bottom: bottomY >= (1.0 - edgeMargin),
            touches_left: leftX <= edgeMargin,
            touches_right: rightX >= (1.0 - edgeMargin)
        )
    }

    #if canImport(Vision) && canImport(CoreVideo) && canImport(ImageIO)
    /// Runs `VNGeneratePersonSegmentationRequest` (.balanced) and summarizes the mask on a 128x96 sampling grid.
    public static func analyzeSegmentation(
        in pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation = .right,
        threshold: UInt8 = 128,
        edgeMargin: Float = 0.015
    ) throws -> MaskSummary? {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        try handler.perform([request])

        guard let maskBuffer = request.results?.first?.pixelBuffer else { return nil }
        CVPixelBufferLockBaseAddress(maskBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(maskBuffer, .readOnly) }

        let srcW = CVPixelBufferGetWidth(maskBuffer)
        let srcH = CVPixelBufferGetHeight(maskBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(maskBuffer)
        guard let baseAddr = CVPixelBufferGetBaseAddress(maskBuffer) else { return nil }
        let ptr = baseAddr.assumingMemoryBound(to: UInt8.self)

        let targetW = 128
        let targetH = 96
        var grid = [UInt8](repeating: 0, count: targetW * targetH)

        for r in 0..<targetH {
            let srcR = min(srcH - 1, (r * srcH) / targetH)
            let rowPtr = ptr.advanced(by: srcR * bytesPerRow)
            for c in 0..<targetW {
                let srcC = min(srcW - 1, (c * srcW) / targetW)
                grid[r * targetW + c] = rowPtr[srcC]
            }
        }

        return summarizeMaskGrid(
            grid: grid,
            width: targetW,
            height: targetH,
            threshold: threshold,
            edgeMargin: edgeMargin
        )
    }
    #endif
}
