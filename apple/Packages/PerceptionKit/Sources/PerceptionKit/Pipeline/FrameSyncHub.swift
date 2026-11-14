import Foundation
import CoreGraphics

/// Synchronizes asynchronous, multi-rate perceptual streams:
/// - 60Hz IMU motion readings
/// - 30/60Hz video data buffer frames
/// - 15Hz Vision body pose keypoints
/// - 8Hz Vision segmentation masks
/// - 4Hz luminance probes
///
/// Produces unified PerceptionFrame and PerceptionBundle objects aligned to the video presentation timestamp.
public final class FrameSyncHub: @unchecked Sendable {
    private let lock = NSLock()
    private var motionRingBuffer: [MotionReading] = []
    private let maxBufferSize: Int = 120 // 2 seconds of 60Hz motion

    private let attitudeTracker: AttitudeTracker
    private let subjectTracker: SubjectTracker
    private var latestSubjects: [Subject] = []
    private var latestSubjectsTimestamp: Double = 0.0
    private var latestSubjectsPosture: Posture = .zero
    private var latestExposure: ExposureSummary = .daylight
    private var latestIntrinsics: CameraIntrinsics = .standardWide
    private var latestLuminance: LuminanceMetrics? = nil

    private var sunAzimuthDeg: Float? = nil
    private var sunElevationDeg: Float? = nil
    private var cameraAzimuthDeg: Float? = nil

    public typealias FrameCallback = @Sendable (PerceptionFrame) -> Void
    public var onFrameAssembled: FrameCallback?

    public typealias BundleCallback = @Sendable (PerceptionBundle) -> Void
    public var onBundleAssembled: BundleCallback?

    public init(
        attitudeTracker: AttitudeTracker = AttitudeTracker(),
        subjectTracker: SubjectTracker = SubjectTracker(),
        onFrameAssembled: FrameCallback? = nil,
        onBundleAssembled: BundleCallback? = nil
    ) {
        self.attitudeTracker = attitudeTracker
        self.subjectTracker = subjectTracker
        self.onFrameAssembled = onFrameAssembled
        self.onBundleAssembled = onBundleAssembled
    }

    /// Ingest a high-frequency (60Hz) motion reading into the temporal ring buffer.
    public func pushMotion(_ reading: MotionReading) {
        lock.lock()
        defer { lock.unlock() }

        // Keep sorted by timestamp
        if motionRingBuffer.isEmpty || reading.timestamp >= motionRingBuffer.last!.timestamp {
            motionRingBuffer.append(reading)
        } else {
            let idx = motionRingBuffer.firstIndex(where: { $0.timestamp > reading.timestamp }) ?? motionRingBuffer.count
            motionRingBuffer.insert(reading, at: idx)
        }

        if motionRingBuffer.count > maxBufferSize {
            motionRingBuffer.removeFirst(motionRingBuffer.count - maxBufferSize)
        }
    }

    /// Linearly interpolates 60Hz IMU motion readings to any presentation timestamp with < 10ms alignment error.
    public func interpolateMotion(at timestamp: Double) -> (reading: MotionReading, alignmentErrorMs: Double, isInterpolated: Bool) {
        lock.lock()
        defer { lock.unlock() }

        guard !motionRingBuffer.isEmpty else {
            return (MotionReading(timestamp: timestamp), 0.0, false)
        }

        if motionRingBuffer.count == 1 {
            let item = motionRingBuffer[0]
            let err = abs(item.timestamp - timestamp) * 1000.0
            return (item, err, false)
        }

        if timestamp <= motionRingBuffer.first!.timestamp {
            let first = motionRingBuffer.first!
            let err = (first.timestamp - timestamp) * 1000.0
            return (first, err, false)
        }

        if timestamp >= motionRingBuffer.last!.timestamp {
            let last = motionRingBuffer.last!
            let err = (timestamp - last.timestamp) * 1000.0
            return (last, err, false)
        }

        // Binary search for bracketing samples: r0.timestamp <= timestamp <= r1.timestamp
        var low = 0
        var high = motionRingBuffer.count - 1

        while (high - low) > 1 {
            let mid = (low + high) / 2
            if motionRingBuffer[mid].timestamp <= timestamp {
                low = mid
            } else {
                high = mid
            }
        }

        let r0 = motionRingBuffer[low]
        let r1 = motionRingBuffer[high]
        let dt = r1.timestamp - r0.timestamp

        if dt <= 1e-9 {
            return (r0, 0.0, false)
        }

        let alpha = (timestamp - r0.timestamp) / dt
        let interpGx = r0.gravityX + alpha * (r1.gravityX - r0.gravityX)
        let interpGy = r0.gravityY + alpha * (r1.gravityY - r0.gravityY)
        let interpGz = r0.gravityZ + alpha * (r1.gravityZ - r0.gravityZ)
        let interpRx = r0.rotationRateX + alpha * (r1.rotationRateX - r0.rotationRateX)
        let interpRy = r0.rotationRateY + alpha * (r1.rotationRateY - r0.rotationRateY)
        let interpRz = r0.rotationRateZ + alpha * (r1.rotationRateZ - r0.rotationRateZ)

        let reading = MotionReading(
            timestamp: timestamp,
            gravityX: interpGx,
            gravityY: interpGy,
            gravityZ: interpGz,
            rotationRateX: interpRx,
            rotationRateY: interpRy,
            rotationRateZ: interpRz
        )

        let alignmentErrorMs = min(timestamp - r0.timestamp, r1.timestamp - timestamp) * 1000.0
        return (reading, alignmentErrorMs, true)
    }

    /// Shifting subject bounding boxes, skeletal joints, and segmentation masks across attitude deltas.
    public func compensateSubjects(
        _ subjects: [Subject],
        fromPosture: Posture,
        toPosture: Posture,
        camera: CameraIntrinsics,
        yawDeltaDeg: Float = 0.0
    ) -> [Subject] {
        let dPitch = toPosture.pitch_deg - fromPosture.pitch_deg
        let dYaw = yawDeltaDeg
        let hfov = max(30.0, camera.hfov_deg)

        let dx = -(dYaw / hfov)
        let dy = (dPitch / hfov)

        guard abs(dx) > 0.0005 || abs(dy) > 0.0005 else {
            return subjects
        }

        return subjects.map { s in
            let newX = max(0.0, min(1.0 - s.bounds.width, s.bounds.x + dx))
            let newY = max(0.0, min(1.0 - s.bounds.height, s.bounds.y + dy))
            let newBounds = NormalizedBox(x: newX, y: newY, width: s.bounds.width, height: s.bounds.height)

            var newJoints: [String: Joint] = [:]
            for (k, j) in s.joints {
                let jx = max(0.0, min(1.0, j.point.x + dx))
                let jy = max(0.0, min(1.0, j.point.y + dy))
                newJoints[k] = Joint(joint_type: j.joint_type, point: NormalizedPoint(x: jx, y: jy), confidence: j.confidence)
            }

            let newMask: MaskSummary?
            if let mask = s.mask_summary {
                newMask = MaskSummarizer.translate(mask, dx: dx, dy: dy)
            } else {
                newMask = nil
            }

            return Subject(
                id: s.id,
                bounds: newBounds,
                joints: newJoints,
                facing: s.facing,
                shot_type: s.shot_type,
                confidence: s.confidence,
                is_group: s.is_group,
                mask_summary: newMask
            )
        }
    }

    /// Update latest detected vision subjects with optional capture timestamp.
    public func updateSubjects(_ subjects: [Subject], timestamp: Double? = nil) {
        lock.lock()
        defer { lock.unlock() }

        let tracked = subjectTracker.track(subjects: subjects)
        self.latestSubjects = tracked

        if let t = timestamp {
            self.latestSubjectsTimestamp = t
            let interp = findNearestMotionReadingInternal(for: t)
            self.latestSubjectsPosture = attitudeTracker.computeRawPosture(reading: interp)
        } else {
            self.latestSubjectsTimestamp = 0.0
            self.latestSubjectsPosture = .zero
        }
    }

    /// Updates the segmentation mask summary on the primary subject without resetting the detection timestamp or posture.
    public func updateMaskSummary(_ mask: MaskSummary) {
        lock.lock()
        defer { lock.unlock() }
        if !latestSubjects.isEmpty {
            var primary = latestSubjects[0]
            primary.mask_summary = mask
            latestSubjects[0] = primary
        }
    }

    /// Update latest camera sensor exposure and optics.
    public func updateOpticsAndExposure(intrinsics: CameraIntrinsics, exposure: ExposureSummary) {
        lock.lock()
        defer { lock.unlock() }
        self.latestIntrinsics = intrinsics
        self.latestExposure = exposure
    }

    /// Update camera metadata (intrinsics and exposure).
    public func updateCameraMetadata(intrinsics: CameraIntrinsics, exposure: ExposureSummary) {
        updateOpticsAndExposure(intrinsics: intrinsics, exposure: exposure)
    }

    /// Update latest probed luminance metrics.
    public func updateLuminance(_ luminance: LuminanceMetrics) {
        lock.lock()
        defer { lock.unlock() }
        self.latestLuminance = luminance
    }

    /// Update astronomical and compass positions for lighting direction estimation.
    public func updateSolarPosition(sunAzimuthDeg: Float?, sunElevationDeg: Float?, cameraAzimuthDeg: Float? = nil) {
        lock.lock()
        defer { lock.unlock() }
        self.sunAzimuthDeg = sunAzimuthDeg
        self.sunElevationDeg = sunElevationDeg
        self.cameraAzimuthDeg = cameraAzimuthDeg
    }

    /// Assembles fused LightContext for a given timestamp.
    public func assembleLightContext(timestamp: Double = 0.0) -> LightContext {
        lock.lock()
        defer { lock.unlock() }

        return LightContext.from(
            exposure: latestExposure,
            luminance: latestLuminance,
            sunAzimuthDeg: sunAzimuthDeg,
            sunElevationDeg: sunElevationDeg,
            cameraAzimuthDeg: cameraAzimuthDeg
        )
    }

    /// Assemble a unified PerceptionFrame corresponding to a video frame's presentation timestamp.
    public func assembleFrame(timestamp: Double) -> PerceptionFrame {
        lock.lock()
        defer { lock.unlock() }

        let (matchedReading, _, _) = findInterpolatedMotionInternal(for: timestamp)
        let posture = attitudeTracker.process(reading: matchedReading)

        let compensatedSubjects: [Subject]
        if latestSubjectsTimestamp > 0.0 && abs(timestamp - latestSubjectsTimestamp) > 0.001 {
            compensatedSubjects = compensateSubjects(
                latestSubjects,
                fromPosture: latestSubjectsPosture,
                toPosture: posture,
                camera: latestIntrinsics
            )
        } else {
            compensatedSubjects = latestSubjects
        }

        let frame = PerceptionFrame(
            t: timestamp,
            subjects: compensatedSubjects,
            primary_subject_index: compensatedSubjects.isEmpty ? nil : 0,
            posture: posture,
            camera: latestIntrinsics,
            exposure: latestExposure
        )

        onFrameAssembled?(frame)
        return frame
    }

    /// Assembles both PerceptionFrame and LightContext into a complete PerceptionBundle.
    public func assemblePerceptionBundle(timestamp: Double) -> PerceptionBundle {
        let (matchedReading, alignmentErrorMs, _) = interpolateMotion(at: timestamp)
        let frame = assembleFrame(timestamp: timestamp)
        let light = assembleLightContext(timestamp: timestamp)

        lock.lock()
        let luma = latestLuminance
        lock.unlock()

        let bundle = PerceptionBundle(
            frame: frame,
            light: light,
            luminance: luma,
            alignmentErrorMs: alignmentErrorMs
        )

        onBundleAssembled?(bundle)
        return bundle
    }

    private func findNearestMotionReadingInternal(for timestamp: Double) -> MotionReading {
        guard !motionRingBuffer.isEmpty else {
            return MotionReading(timestamp: timestamp)
        }
        var closest = motionRingBuffer.last!
        var minDiff = abs(closest.timestamp - timestamp)

        for reading in motionRingBuffer.reversed() {
            let diff = abs(reading.timestamp - timestamp)
            if diff < minDiff {
                minDiff = diff
                closest = reading
            } else if reading.timestamp < timestamp {
                break
            }
        }
        return closest
    }

    private func findInterpolatedMotionInternal(for timestamp: Double) -> (reading: MotionReading, alignmentErrorMs: Double, isInterpolated: Bool) {
        guard !motionRingBuffer.isEmpty else {
            return (MotionReading(timestamp: timestamp), 0.0, false)
        }

        if motionRingBuffer.count == 1 {
            let item = motionRingBuffer[0]
            let err = abs(item.timestamp - timestamp) * 1000.0
            return (item, err, false)
        }

        if timestamp <= motionRingBuffer.first!.timestamp {
            let first = motionRingBuffer.first!
            let err = (first.timestamp - timestamp) * 1000.0
            return (first, err, false)
        }

        if timestamp >= motionRingBuffer.last!.timestamp {
            let last = motionRingBuffer.last!
            let err = (timestamp - last.timestamp) * 1000.0
            return (last, err, false)
        }

        var low = 0
        var high = motionRingBuffer.count - 1
        while (high - low) > 1 {
            let mid = (low + high) / 2
            if motionRingBuffer[mid].timestamp <= timestamp {
                low = mid
            } else {
                high = mid
            }
        }

        let r0 = motionRingBuffer[low]
        let r1 = motionRingBuffer[high]
        let dt = r1.timestamp - r0.timestamp
        if dt <= 1e-9 {
            return (r0, 0.0, false)
        }

        let alpha = (timestamp - r0.timestamp) / dt
        let interpGx = r0.gravityX + alpha * (r1.gravityX - r0.gravityX)
        let interpGy = r0.gravityY + alpha * (r1.gravityY - r0.gravityY)
        let interpGz = r0.gravityZ + alpha * (r1.gravityZ - r0.gravityZ)
        let interpRx = r0.rotationRateX + alpha * (r1.rotationRateX - r0.rotationRateX)
        let interpRy = r0.rotationRateY + alpha * (r1.rotationRateY - r0.rotationRateY)
        let interpRz = r0.rotationRateZ + alpha * (r1.rotationRateZ - r0.rotationRateZ)

        let reading = MotionReading(
            timestamp: timestamp,
            gravityX: interpGx,
            gravityY: interpGy,
            gravityZ: interpGz,
            rotationRateX: interpRx,
            rotationRateY: interpRy,
            rotationRateZ: interpRz
        )
        let err = min(timestamp - r0.timestamp, r1.timestamp - timestamp) * 1000.0
        return (reading, err, true)
    }

    /// Clear temporal state.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        motionRingBuffer.removeAll()
        latestSubjects.removeAll()
        latestSubjectsTimestamp = 0.0
        latestSubjectsPosture = .zero
        latestLuminance = nil
        sunAzimuthDeg = nil
        sunElevationDeg = nil
        cameraAzimuthDeg = nil
        attitudeTracker.reset()
        subjectTracker.reset()
    }
}
