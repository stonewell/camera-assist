import Foundation
import CoreGraphics

#if canImport(CoreVideo)
import CoreVideo
#endif
#if canImport(Vision)
import Vision
#endif
#if canImport(ImageIO)
import ImageIO
#endif

/// Input container representing a single video frame and its associated capture metadata.
public struct PerceptionVideoFrameInput: Sendable {
    public let timestamp: Double
    public let intrinsics: CameraIntrinsics
    public let exposure: ExposureSummary
    public let orientation: CGImagePropertyOrientation

    #if canImport(CoreVideo)
    public let pixelBuffer: CVPixelBuffer?
    #endif

    #if canImport(CoreVideo)
    public init(
        timestamp: Double,
        pixelBuffer: CVPixelBuffer? = nil,
        intrinsics: CameraIntrinsics = .standardWide,
        exposure: ExposureSummary = .daylight,
        orientation: CGImagePropertyOrientation = .right
    ) {
        self.timestamp = timestamp
        self.pixelBuffer = pixelBuffer
        self.intrinsics = intrinsics
        self.exposure = exposure
        self.orientation = orientation
    }
    #else
    public init(
        timestamp: Double,
        intrinsics: CameraIntrinsics = .standardWide,
        exposure: ExposureSummary = .daylight,
        orientation: CGImagePropertyOrientation = .right
    ) {
        self.timestamp = timestamp
        self.intrinsics = intrinsics
        self.exposure = exposure
        self.orientation = orientation
    }
    #endif
}

/// Real-time execution telemetry for multi-tiered Vision tasks.
public struct VisionProcessorTelemetry: Sendable, Codable, Equatable {
    public var poseExecutionCount: Int
    public var maskExecutionCount: Int
    public var faceExecutionCount: Int
    public var lumaExecutionCount: Int
    public var lastPoseDurationMs: Double
    public var lastMaskDurationMs: Double

    public init(
        poseExecutionCount: Int = 0,
        maskExecutionCount: Int = 0,
        faceExecutionCount: Int = 0,
        lumaExecutionCount: Int = 0,
        lastPoseDurationMs: Double = 0.0,
        lastMaskDurationMs: Double = 0.0
    ) {
        self.poseExecutionCount = poseExecutionCount
        self.maskExecutionCount = maskExecutionCount
        self.faceExecutionCount = faceExecutionCount
        self.lumaExecutionCount = lumaExecutionCount
        self.lastPoseDurationMs = lastPoseDurationMs
        self.lastMaskDurationMs = lastMaskDurationMs
    }
}

/// Orchestrates tiered multi-rate Vision execution and feeds the FrameSyncHub.
public final class VisionFrameProcessor: @unchecked Sendable {
    public let scheduler: PerceptionScheduler
    public let poseAnalyzer: BodyPoseAnalyzer
    public let syncHub: FrameSyncHub

    public private(set) var telemetry = VisionProcessorTelemetry()

    // Test / Simulator fallback injections
    public var fallbackSubjects: [Subject]? = nil
    public var fallbackMaskGrid: (grid: [UInt8], width: Int, height: Int)? = nil
    public var fallbackFaceBoxes: [NormalizedBox]? = nil
    public var syntheticLumaGrid: (grid: [UInt8], width: Int, height: Int)? = nil

    public private(set) var lastSubjects: [Subject] = []
    public private(set) var lastMaskSummary: MaskSummary? = nil
    public private(set) var lastLuminance: LuminanceMetrics? = nil

    private var lastPoseFoundSubject: Bool = false
    private var lastSubjectsTimestamp: Double = 0.0

    public init(
        scheduler: PerceptionScheduler = PerceptionScheduler(),
        poseAnalyzer: BodyPoseAnalyzer = BodyPoseAnalyzer(),
        syncHub: FrameSyncHub = FrameSyncHub()
    ) {
        self.scheduler = scheduler
        self.poseAnalyzer = poseAnalyzer
        self.syncHub = syncHub
    }

    /// Evaluates scheduled tasks for `input`, executes required Vision & luminance steps, and returns a unified PerceptionBundle.
    public func processFrame(
        input: PerceptionVideoFrameInput,
        thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    ) -> PerceptionBundle {
        let schedule = scheduler.schedule(
            at: input.timestamp,
            thermalState: thermalState,
            lastPoseHadSubject: lastPoseFoundSubject
        )

        var subjectsUpdatedThisFrame = false

        // 1. 15Hz Body Pose Detection
        if schedule.runBodyPose {
            let start = CFAbsoluteTimeGetCurrent()
            telemetry.poseExecutionCount += 1

            var detectedSubjects: [Subject] = []
            var executedPose = false
            if let fallback = fallbackSubjects {
                detectedSubjects = fallback
                executedPose = true
            } else {
                #if canImport(Vision) && canImport(CoreVideo) && canImport(ImageIO)
                if let pb = input.pixelBuffer {
                    detectedSubjects = (try? poseAnalyzer.detectBodyPose(in: pb, orientation: input.orientation, timestamp: input.timestamp)) ?? []
                    executedPose = true
                }
                #endif
            }

            if executedPose {
                lastPoseFoundSubject = !detectedSubjects.isEmpty
                lastSubjects = detectedSubjects
                lastSubjectsTimestamp = input.timestamp
                subjectsUpdatedThisFrame = true
            }

            telemetry.lastPoseDurationMs = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
        }

        // 2. 10Hz Face Fallback Detection (when pose found no subjects)
        if schedule.runFaceFallback && !lastPoseFoundSubject {
            telemetry.faceExecutionCount += 1

            var faceBoxes: [NormalizedBox] = []
            var executedFace = false
            if let fallbackFaces = fallbackFaceBoxes {
                faceBoxes = fallbackFaces
                executedFace = true
            } else {
                #if canImport(Vision) && canImport(CoreVideo) && canImport(ImageIO)
                if let pb = input.pixelBuffer {
                    faceBoxes = (try? poseAnalyzer.detectFaceRectangles(in: pb, orientation: input.orientation)) ?? []
                    executedFace = true
                }
                #endif
            }

            if executedFace {
                if !faceBoxes.isEmpty {
                    lastSubjects = poseAnalyzer.subjectsFromFaceBoxes(faceBoxes)
                    lastSubjectsTimestamp = input.timestamp
                    subjectsUpdatedThisFrame = true
                } else if !schedule.runBodyPose {
                    if !lastSubjects.isEmpty {
                        lastSubjects.removeAll()
                        lastSubjectsTimestamp = input.timestamp
                        subjectsUpdatedThisFrame = true
                    }
                }
            }
        }

        // 3. 8Hz Person Segmentation Mask
        if schedule.runSegmentationMask {
            let start = CFAbsoluteTimeGetCurrent()
            telemetry.maskExecutionCount += 1

            var mask: MaskSummary? = nil
            if let fallback = fallbackMaskGrid {
                mask = MaskSummarizer.summarizeMaskGrid(grid: fallback.grid, width: fallback.width, height: fallback.height)
            } else {
                #if canImport(Vision) && canImport(CoreVideo) && canImport(ImageIO)
                if let pb = input.pixelBuffer {
                    mask = try? MaskSummarizer.analyzeSegmentation(in: pb, orientation: input.orientation)
                }
                #endif
            }

            if let m = mask {
                lastMaskSummary = m
                if !lastSubjects.isEmpty {
                    var primary = lastSubjects[0]
                    primary.mask_summary = m
                    lastSubjects[0] = primary
                    syncHub.updateMaskSummary(m)
                }
            }

            telemetry.lastMaskDurationMs = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
        }

        // 4. 4Hz Luminance Probe
        if schedule.runLumaProbe {
            telemetry.lumaExecutionCount += 1

            let primaryBox = lastSubjects.first?.bounds
            if let synth = syntheticLumaGrid {
                lastLuminance = PerceptionScheduler.probeLuminance(
                    lumaGrid: synth.grid,
                    width: synth.width,
                    height: synth.height,
                    subjectBox: primaryBox
                )
            } else {
                #if canImport(CoreVideo)
                if let pb = input.pixelBuffer {
                    lastLuminance = PerceptionScheduler.probePixelBufferLuminance(
                        pb,
                        subjectBox: primaryBox
                    )
                }
                #endif
            }
        }

        // 5. Update FrameSyncHub state
        if subjectsUpdatedThisFrame {
            syncHub.updateSubjects(lastSubjects, timestamp: lastSubjectsTimestamp)
        }
        syncHub.updateCameraMetadata(intrinsics: input.intrinsics, exposure: input.exposure)
        if let luma = lastLuminance {
            syncHub.updateLuminance(luma)
        }

        // 6. Assemble and return PerceptionBundle
        return syncHub.assemblePerceptionBundle(timestamp: input.timestamp)
    }

    public func reset() {
        scheduler.reset()
        poseAnalyzer.reset()
        syncHub.reset()
        telemetry = VisionProcessorTelemetry()
        lastSubjects.removeAll()
        lastMaskSummary = nil
        lastLuminance = nil
        lastPoseFoundSubject = false
        lastSubjectsTimestamp = 0.0
        fallbackSubjects = nil
        fallbackMaskGrid = nil
        fallbackFaceBoxes = nil
        syntheticLumaGrid = nil
    }
}
