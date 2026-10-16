import Foundation
import CoreGraphics

#if canImport(ImageIO)
import ImageIO
#endif

/// Geometric coordinate transforms between Vision framework and SwiftUI / UIKit viewport.
public enum VisionOrientationMapper {
    /// Maps back-camera capture rotation angle to CGImagePropertyOrientation.
    public static func visionOrientation(captureAngle: CGFloat) -> CGImagePropertyOrientation {
        switch Int(captureAngle) {
        case 90:
            return .right      // Portrait upright
        case 180:
            return .down       // Landscape left
        case 270:
            return .left       // Portrait upside down
        default:
            return .up         // 0: Landscape right
        }
    }

    /// Converts normalized point from Vision space (origin bottom-left) to UI space (origin top-left).
    public static func pointFromVisionToUI(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x, y: 1.0 - p.y)
    }

    /// Converts normalized rect from Vision space (origin bottom-left) to UI space (origin top-left).
    public static func rectFromVisionToUI(_ r: CGRect) -> CGRect {
        CGRect(
            x: r.origin.x,
            y: 1.0 - (r.origin.y + r.size.height),
            width: r.size.width,
            height: r.size.height
        )
    }

    /// Converts normalized UI rect (in [0, 1] range) to actual screen view coordinates
    /// under AVLayerVideoGravity.resizeAspect (4:3 aspect ratio fitted into container view).
    public static func mapNormalizedRectToAspectFit(
        normalizedRect: CGRect,
        containerBounds: CGRect,
        contentAspectRatio: CGFloat = 4.0 / 3.0
    ) -> CGRect {
        let containerAspect = containerBounds.width / containerBounds.height

        var fittedWidth: CGFloat
        var fittedHeight: CGFloat
        var offsetX: CGFloat = 0.0
        var offsetY: CGFloat = 0.0

        if containerAspect > contentAspectRatio {
            // Container is wider than 4:3 -> letterbox on left/right
            fittedHeight = containerBounds.height
            fittedWidth = fittedHeight * contentAspectRatio
            offsetX = (containerBounds.width - fittedWidth) / 2.0
        } else {
            // Container is taller than 4:3 -> pillarbox on top/bottom
            fittedWidth = containerBounds.width
            fittedHeight = fittedWidth / contentAspectRatio
            offsetY = (containerBounds.height - fittedHeight) / 2.0
        }

        return CGRect(
            x: offsetX + normalizedRect.origin.x * fittedWidth,
            y: offsetY + normalizedRect.origin.y * fittedHeight,
            width: normalizedRect.size.width * fittedWidth,
            height: normalizedRect.size.height * fittedHeight
        )
    }
}
