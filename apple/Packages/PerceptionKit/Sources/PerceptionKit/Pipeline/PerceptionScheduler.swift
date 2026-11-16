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

    /// Alias for runFaceFallback when using face rectangles as pose fallback.
    public var runFaceRectangles: Bool {
        runFaceFallback
    }

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
    private let lock = NSLock()
    private var lastPoseTime: Double = -.infinity
    private var lastMaskTime: Double = -.infinity
    private var lastFaceTime: Double = -.infinity
    private var lastLumaTime: Double = -.infinity

    public var basePoseHz: Double = 15.0
    public var baseMaskHz: Double = 8.0
    public var baseFaceHz: Double = 10.0
    public var baseLumaHz: Double = 4.0
    public let cadenceEpsilon: Double = 1e-6

    public init() {}

    private func thermalPolicy(for thermalState: ProcessInfo.ThermalState) -> (rateMultiplier: Double, allowMask: Bool) {
        switch thermalState {
        case .nominal, .fair:
            return (1.0, true)
        case .serious:
            return (0.5, true)
        case .critical:
            return (0.25, false)
        @unknown default:
            return (1.0, true)
        }
    }

    /// Evaluates which perception tasks should execute at `timestamp` given the current thermal state.
    public func schedule(
        at timestamp: Double,
        thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState,
        lastPoseHadSubject: Bool = true
    ) -> ScheduledPerceptionTasks {
        lock.lock()
        defer { lock.unlock() }

        let (rateMultiplier, allowMask) = thermalPolicy(for: thermalState)

        let poseInterval = 1.0 / (basePoseHz * rateMultiplier)
        let maskInterval = 1.0 / (baseMaskHz * rateMultiplier)
        let faceInterval = 1.0 / (baseFaceHz * rateMultiplier)
        let lumaInterval = 1.0 / (baseLumaHz * rateMultiplier)

        let runPose = (timestamp - lastPoseTime) >= (poseInterval - cadenceEpsilon)
        if runPose { lastPoseTime = timestamp }

        let runMask = allowMask && (timestamp - lastMaskTime) >= (maskInterval - cadenceEpsilon)
        if runMask { lastMaskTime = timestamp }

        let runFace = !lastPoseHadSubject && (timestamp - lastFaceTime) >= (faceInterval - cadenceEpsilon)
        if runFace { lastFaceTime = timestamp }

        let runLuma = (timestamp - lastLumaTime) >= (lumaInterval - cadenceEpsilon)
        if runLuma { lastLumaTime = timestamp }

        return ScheduledPerceptionTasks(
            runBodyPose: runPose,
            runSegmentationMask: runMask,
            runFaceFallback: runFace,
            runLumaProbe: runLuma
        )
    }

    /// Checks whether face fallback is due at `timestamp` (and records `lastFaceTime` if so),
    /// used when body pose transitions to empty within the same frame.
    public func tryTriggerFaceFallback(
        at timestamp: Double,
        thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let (rateMultiplier, _) = thermalPolicy(for: thermalState)
        let faceInterval = 1.0 / (baseFaceHz * rateMultiplier)
        let runFace = (timestamp - lastFaceTime) >= (faceInterval - cadenceEpsilon)
        if runFace {
            lastFaceTime = timestamp
        }
        return runFace
    }

    /// Evaluates detailed luminance metrics from an 8-bit luma grid.
    public static func probeLuminance(
        lumaGrid: [UInt8],
        width: Int,
        height: Int,
        subjectBox: NormalizedBox? = nil,
        faceBox: NormalizedBox? = nil
    ) -> LuminanceMetrics {
        guard width > 0, height > 0, lumaGrid.count >= width * height else {
            return LuminanceMetrics()
        }

        let totalPixels = width * height
        var totalSum: Double = 0.0
        var highlightClipCount: Int = 0
        var shadowCrushCount: Int = 0

        // Compute face / subject region bounds
        let faceRegion: (minC: Int, maxC: Int, minR: Int, maxR: Int)?
        let subjectRegion: (minC: Int, maxC: Int, minR: Int, maxR: Int)?

        if let fb = faceBox {
            let minC = max(0, min(width - 1, Int(fb.min_x * Float(width))))
            let maxC = max(0, min(width - 1, Int(fb.max_x * Float(width))))
            let minR = max(0, min(height - 1, Int(fb.min_y * Float(height))))
            let maxR = max(0, min(height - 1, Int(fb.max_y * Float(height))))
            faceRegion = (minC, maxC, minR, maxR)
            if let sb = subjectBox {
                let sMinC = max(0, min(width - 1, Int(sb.min_x * Float(width))))
                let sMaxC = max(0, min(width - 1, Int(sb.max_x * Float(width))))
                let sMinR = max(0, min(height - 1, Int(sb.min_y * Float(height))))
                let sMaxR = max(0, min(height - 1, Int(sb.max_y * Float(height))))
                subjectRegion = (sMinC, sMaxC, sMinR, sMaxR)
            } else {
                subjectRegion = faceRegion
            }
        } else if let sb = subjectBox {
            let minC = max(0, min(width - 1, Int(sb.min_x * Float(width))))
            let maxC = max(0, min(width - 1, Int(sb.max_x * Float(width))))
            let minR = max(0, min(height - 1, Int(sb.min_y * Float(height))))
            let maxR = max(0, min(height - 1, Int((sb.min_y + sb.height * 0.35) * Float(height))))
            faceRegion = (minC, maxC, minR, maxR)
            let sMaxR = max(0, min(height - 1, Int(sb.max_y * Float(height))))
            subjectRegion = (minC, maxC, minR, sMaxR)
        } else {
            faceRegion = nil
            subjectRegion = nil
        }

        var faceSum: Double = 0.0
        var faceCount: Int = 0
        var bgSum: Double = 0.0
        var bgCount: Int = 0

        for r in 0..<height {
            let rowOffset = r * width
            for c in 0..<width {
                let val = lumaGrid[rowOffset + c]
                let dVal = Double(val)
                totalSum += dVal

                if val >= 250 {
                    highlightClipCount += 1
                } else if val <= 10 {
                    shadowCrushCount += 1
                }

                if let fr = faceRegion, r >= fr.minR && r <= fr.maxR && c >= fr.minC && c <= fr.maxC {
                    faceSum += dVal
                    faceCount += 1
                }

                if let sr = subjectRegion {
                    if !(r >= sr.minR && r <= sr.maxR && c >= sr.minC && c <= sr.maxC) {
                        bgSum += dVal
                        bgCount += 1
                    }
                } else {
                    bgSum += dVal
                    bgCount += 1
                }
            }
        }

        let meanLuma = Float(totalSum / Double(totalPixels) / 255.0)
        let highlightClipRatio = Float(highlightClipCount) / Float(totalPixels)
        let shadowCrushRatio = Float(shadowCrushCount) / Float(totalPixels)

        let faceToBgRatio: Float
        if faceCount > 0 && bgCount > 0 {
            let faceMean = faceSum / Double(faceCount)
            let bgMean = max(1.0, bgSum / Double(bgCount))
            faceToBgRatio = Float(faceMean / bgMean)
        } else {
            faceToBgRatio = 1.0
        }

        let isBacklit = faceToBgRatio < 0.45 || (faceToBgRatio < 0.60 && highlightClipRatio > 0.03)

        return LuminanceMetrics(
            mean_luma: meanLuma,
            face_to_bg_ratio: faceToBgRatio,
            highlight_clip_ratio: highlightClipRatio,
            shadow_crush_ratio: shadowCrushRatio,
            is_backlit: isBacklit
        )
    }

    #if canImport(CoreVideo)
    /// Probes luminance metrics directly from a CVPixelBuffer supporting 420f/420v planar, OneComponent8, and 32BGRA formats.
    public static func probePixelBufferLuminance(
        _ pixelBuffer: CVPixelBuffer,
        subjectBox: NormalizedBox? = nil,
        faceBox: NormalizedBox? = nil,
        gridWidth: Int = 64,
        gridHeight: Int = 48
    ) -> LuminanceMetrics {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let isPlanar = CVPixelBufferIsPlanar(pixelBuffer)
        let targetW = max(8, gridWidth)
        let targetH = max(6, gridHeight)
        var grid = [UInt8](repeating: 128, count: targetW * targetH)

        if isPlanar && (format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange || format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
            // Y-plane is plane 0
            guard let baseAddr = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else {
                return LuminanceMetrics()
            }
            let srcW = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
            let srcH = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
            let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            let ptr = baseAddr.assumingMemoryBound(to: UInt8.self)

            for r in 0..<targetH {
                let srcR = min(srcH - 1, (r * srcH) / targetH)
                let rowPtr = ptr.advanced(by: srcR * bytesPerRow)
                for c in 0..<targetW {
                    let srcC = min(srcW - 1, (c * srcW) / targetW)
                    grid[r * targetW + c] = rowPtr[srcC]
                }
            }
        } else if format == kCVPixelFormatType_OneComponent8 {
            guard let baseAddr = CVPixelBufferGetBaseAddress(pixelBuffer) else {
                return LuminanceMetrics()
            }
            let srcW = CVPixelBufferGetWidth(pixelBuffer)
            let srcH = CVPixelBufferGetHeight(pixelBuffer)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let ptr = baseAddr.assumingMemoryBound(to: UInt8.self)

            for r in 0..<targetH {
                let srcR = min(srcH - 1, (r * srcH) / targetH)
                let rowPtr = ptr.advanced(by: srcR * bytesPerRow)
                for c in 0..<targetW {
                    let srcC = min(srcW - 1, (c * srcW) / targetW)
                    grid[r * targetW + c] = rowPtr[srcC]
                }
            }
        } else if format == kCVPixelFormatType_32BGRA {
            guard let baseAddr = CVPixelBufferGetBaseAddress(pixelBuffer) else {
                return LuminanceMetrics()
            }
            let srcW = CVPixelBufferGetWidth(pixelBuffer)
            let srcH = CVPixelBufferGetHeight(pixelBuffer)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let ptr = baseAddr.assumingMemoryBound(to: UInt8.self)

            for r in 0..<targetH {
                let srcR = min(srcH - 1, (r * srcH) / targetH)
                let rowPtr = ptr.advanced(by: srcR * bytesPerRow)
                for c in 0..<targetW {
                    let srcC = min(srcW - 1, (c * srcW) / targetW)
                    let b = Double(rowPtr[srcC * 4])
                    let g = Double(rowPtr[srcC * 4 + 1])
                    let red = Double(rowPtr[srcC * 4 + 2])
                    let y = UInt8(max(0.0, min(255.0, 0.299 * red + 0.587 * g + 0.114 * b)))
                    grid[r * targetW + c] = y
                }
            }
        }

        return probeLuminance(
            lumaGrid: grid,
            width: targetW,
            height: targetH,
            subjectBox: subjectBox,
            faceBox: faceBox
        )
    }
    #endif

    /// Computes face-to-background luminance ratio from an 8-bit luma grid (e.g. Y-plane of `420v`)
    /// to detect severe backlight conditions (`faceToBgRatio < 0.45`).
    public static func computeFaceToBackgroundRatio(
        lumaGrid: [UInt8],
        width: Int,
        height: Int,
        subjectBox: NormalizedBox
    ) -> Float {
        return probeLuminance(lumaGrid: lumaGrid, width: width, height: height, subjectBox: subjectBox).face_to_bg_ratio
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        lastPoseTime = -.infinity
        lastMaskTime = -.infinity
        lastFaceTime = -.infinity
        lastLumaTime = -.infinity
    }
}
