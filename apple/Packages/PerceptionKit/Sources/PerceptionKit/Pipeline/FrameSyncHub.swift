import Foundation
import CoreGraphics

/// Synchronizes asynchronous, multi-rate perceptual streams:
/// - 60Hz IMU motion readings
/// - 30/60Hz video data buffer frames
/// - 15Hz Vision body pose keypoints
/// - 8Hz Vision segmentation masks
///
/// Produces unified PerceptionFrame objects aligned to the video presentation timestamp.
public final class FrameSyncHub: @unchecked Sendable {
    private let lock = NSLock()
    private var motionRingBuffer: [MotionReading] = []
    private let maxBufferSize: Int = 120 // 2 seconds of 60Hz motion

    private let attitudeTracker: AttitudeTracker
    private let subjectTracker: SubjectTracker
    private var latestSubjects: [Subject] = []
    private var latestExposure: ExposureSummary = .daylight
    private var latestIntrinsics: CameraIntrinsics = .standardWide

    public typealias FrameCallback = @Sendable (PerceptionFrame) -> Void
    public var onFrameAssembled: FrameCallback?

    public init(
        attitudeTracker: AttitudeTracker = AttitudeTracker(),
        subjectTracker: SubjectTracker = SubjectTracker(),
        onFrameAssembled: FrameCallback? = nil
    ) {
        self.attitudeTracker = attitudeTracker
        self.subjectTracker = subjectTracker
        self.onFrameAssembled = onFrameAssembled
    }

    /// Ingest a high-frequency (60Hz) motion reading into the temporal ring buffer.
    public func pushMotion(_ reading: MotionReading) {
        lock.lock()
        defer { lock.unlock() }

        motionRingBuffer.append(reading)
        if motionRingBuffer.count > maxBufferSize {
            motionRingBuffer.removeFirst(motionRingBuffer.count - maxBufferSize)
        }
    }

    /// Update latest detected vision subjects.
    public func updateSubjects(_ subjects: [Subject]) {
        lock.lock()
        let tracked = subjectTracker.track(subjects: subjects)
        self.latestSubjects = tracked
        lock.unlock()
    }

    /// Update latest camera sensor exposure and optics.
    public func updateOpticsAndExposure(intrinsics: CameraIntrinsics, exposure: ExposureSummary) {
        lock.lock()
        self.latestIntrinsics = intrinsics
        self.latestExposure = exposure
        lock.unlock()
    }

    /// Assemble a unified PerceptionFrame corresponding to a video frame's presentation timestamp.
    public func assembleFrame(timestamp: Double) -> PerceptionFrame {
        lock.lock()
        defer { lock.unlock() }

        // Find nearest or interpolate motion reading for timestamp
        let matchedReading = findNearestMotionReading(for: timestamp)
        let posture = attitudeTracker.process(reading: matchedReading)

        let frame = PerceptionFrame(
            t: timestamp,
            subjects: latestSubjects,
            primary_subject_index: latestSubjects.isEmpty ? nil : 0,
            posture: posture,
            camera: latestIntrinsics,
            exposure: latestExposure
        )

        onFrameAssembled?(frame)
        return frame
    }

    /// Interpolates or finds the closest motion reading in the buffer.
    private func findNearestMotionReading(for timestamp: Double) -> MotionReading {
        guard !motionRingBuffer.isEmpty else {
            return MotionReading(timestamp: timestamp)
        }

        if motionRingBuffer.count == 1 {
            return motionRingBuffer[0]
        }

        // Linear scan from newest to oldest
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

    /// Clear temporal state.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        motionRingBuffer.removeAll()
        latestSubjects.removeAll()
        attitudeTracker.reset()
        subjectTracker.reset()
    }
}
