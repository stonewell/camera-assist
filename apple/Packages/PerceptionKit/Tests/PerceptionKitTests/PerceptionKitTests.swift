import XCTest
@testable import PerceptionKit

final class PerceptionKitTests: XCTestCase {
    func testOneEuroFilterStationaryJitterSuppression() {
        let filter = OneEuroFilter(minCutoff: 1.0, beta: 0.01)
        var t = 0.0
        let baseVal = 10.0
        var filteredValues: [Double] = []

        // Simulate noisy stationary signal: 10.0 +/- 0.5
        for i in 0..<30 {
            t += 0.016
            let noise = (Double(i % 5) - 2.0) * 0.2
            let filtered = filter.filter(baseVal + noise, timestamp: t)
            filteredValues.append(filtered)
        }

        // Output should stay close to 10.0 with minimal variance
        let last = filteredValues.last!
        XCTAssertEqual(last, 10.0, accuracy: 0.3)
    }

    func testAttitudeTrackerRollAndElevation() {
        let tracker = AttitudeTracker()
        tracker.captureAngleDeg = 90.0 // Portrait

        // Phone tilted 5 degrees clockwise (gx > 0, gy = -cos(5°))
        let rad = 5.0 * Double.pi / 180.0
        let reading = MotionReading(
            timestamp: 1.0,
            gravityX: sin(rad),
            gravityY: -cos(rad),
            gravityZ: 0.0
        )

        let posture = tracker.process(reading: reading)
        XCTAssertEqual(posture.roll_deg, 5.0, accuracy: 0.2)
        XCTAssertEqual(posture.pitch_deg, 0.0, accuracy: 0.2)
        XCTAssertFalse(posture.is_flatish)
    }

    func testBodyPoseAnalyzerNormalizationAndNeckSynthesis() {
        let analyzer = BodyPoseAnalyzer(minConfidence: 0.3)
        let rawKeypoints: [String: (point: CGPoint, confidence: Float)] = [
            "nose": (point: CGPoint(x: 0.5, y: 0.8), confidence: 0.95), // Vision bottom-left: y=0.8 is near top
            "lShoulder": (point: CGPoint(x: 0.4, y: 0.7), confidence: 0.90),
            "rShoulder": (point: CGPoint(x: 0.6, y: 0.7), confidence: 0.90),
            "lAnkle": (point: CGPoint(x: 0.4, y: 0.1), confidence: 0.85),
            "rWrist": (point: CGPoint(x: 0.7, y: 0.5), confidence: 0.15) // Below threshold -> filtered
        ]

        let joints = analyzer.processKeypoints(rawKeypoints, timestamp: 1.0)
        XCTAssertNil(joints["RightWrist"])
        XCTAssertNotNil(joints["Nose"])
        XCTAssertNotNil(joints["Neck"]) // Synthesized from LeftShoulder + RightShoulder

        // Nose in Vision (x=0.5, y=0.8) -> top-left UI should have y = 1.0 - 0.8 = 0.2
        let nose = joints["Nose"]!
        XCTAssertEqual(nose.joint_type, .Nose)
        XCTAssertEqual(nose.point.x, 0.5, accuracy: 0.01)
        XCTAssertEqual(nose.point.y, 0.2, accuracy: 0.01)
        XCTAssertEqual(nose.confidence, 0.95, accuracy: 0.001)

        let neck = joints["Neck"]!
        XCTAssertEqual(neck.point.x, 0.5, accuracy: 0.01)
        XCTAssertEqual(neck.point.y, 0.3, accuracy: 0.01)
    }

    func testMaskSummarizerTouchAndGridScanner() {
        let bbox = NormalizedBox(min_x: 0.005, min_y: 0.01, max_x: 0.8, max_y: 0.99)
        let summary = MaskSummarizer.summarize(bbox: bbox)

        XCTAssertTrue(summary.touches_top)
        XCTAssertTrue(summary.touches_left)
        XCTAssertTrue(summary.touches_bottom)
        XCTAssertFalse(summary.touches_right)

        // Test 128x96 downsampled segmentation grid scanner
        let w = 128, h = 96
        var grid = [UInt8](repeating: 0, count: w * h)
        for r in 10..<85 {
            for c in 40..<88 {
                grid[r * w + c] = 255
            }
        }
        let gridSummary = MaskSummarizer.summarizeMaskGrid(grid: grid, width: w, height: h)
        XCTAssertNotNil(gridSummary)
        XCTAssertEqual(gridSummary!.head_cols.count, 2)
        XCTAssertFalse(gridSummary!.touches_top)
    }

    func testPerceptionSchedulerMultiRateAndLuma() {
        let scheduler = PerceptionScheduler()
        let first = scheduler.schedule(at: 1.0, thermalState: .nominal, lastPoseHadSubject: false)
        XCTAssertTrue(first.runBodyPose)
        XCTAssertTrue(first.runSegmentationMask)
        XCTAssertTrue(first.runFaceFallback)
        XCTAssertTrue(first.runLumaProbe)

        let immediate = scheduler.schedule(at: 1.01, thermalState: .nominal, lastPoseHadSubject: true)
        XCTAssertFalse(immediate.runBodyPose)
        XCTAssertFalse(immediate.runSegmentationMask)

        let critical = scheduler.schedule(at: 2.0, thermalState: .critical, lastPoseHadSubject: true)
        XCTAssertTrue(critical.runBodyPose)
        XCTAssertFalse(critical.runSegmentationMask)
    }

    func testSubjectTrackerIoUAndGroupMerging() {
        let box1 = NormalizedBox(min_x: 0.2, min_y: 0.2, max_x: 0.4, max_y: 0.8)
        let box2 = NormalizedBox(min_x: 0.3, min_y: 0.2, max_x: 0.5, max_y: 0.8)

        let iou = SubjectTracker.computeIoU(box1, box2)
        XCTAssertGreaterThan(iou, 0.3)

        let tracker = SubjectTracker()
        let s1 = Subject(id: "p1", bbox: NormalizedBox(min_x: 0.2, min_y: 0.2, max_x: 0.4, max_y: 0.8))
        let s2 = Subject(id: "p2", bbox: NormalizedBox(min_x: 0.45, min_y: 0.2, max_x: 0.65, max_y: 0.8))

        let tracked = tracker.track(subjects: [s1, s2])
        // Should produce merged group subject as primary (count == 3: group, s1, s2)
        XCTAssertEqual(tracked.count, 3)
        XCTAssertTrue(tracked[0].is_group)
        XCTAssertEqual(tracked[0].bbox.min_x, 0.2, accuracy: 0.01)
        XCTAssertEqual(tracked[0].bbox.max_x, 0.65, accuracy: 0.01)
    }

    func testFrameSyncHubAndJSONSerialization() throws {
        let hub = FrameSyncHub()

        // Push 60Hz motion readings
        hub.pushMotion(MotionReading(timestamp: 10.000, gravityX: 0.0, gravityY: -1.0, gravityZ: 0.0))
        hub.pushMotion(MotionReading(timestamp: 10.016, gravityX: 0.05, gravityY: -0.998, gravityZ: 0.0))
        hub.pushMotion(MotionReading(timestamp: 10.033, gravityX: 0.05, gravityY: -0.998, gravityZ: 0.0))

        // Push detected subjects using canonical schema
        let s1 = Subject(
            id: 1,
            bounds: NormalizedBox(min_x: 0.25, min_y: 0.15, max_x: 0.75, max_y: 0.85),
            joints: ["Nose": Joint(joint_type: .Nose, x: 0.5, y: 0.2, confidence: 0.9)],
            facing: "Frontal",
            shot_type: "FullBody",
            confidence: 0.98,
            is_group: false,
            mask_summary: MaskSummary(top_y: 0.15)
        )
        hub.updateSubjects([s1])

        // Assemble frame at video timestamp 10.018
        let frame = hub.assembleFrame(timestamp: 10.018)
        XCTAssertEqual(frame.t, 10.018)
        XCTAssertEqual(frame.subjects.count, 1)
        XCTAssertEqual(frame.primary_subject_index, 0)

        // Serialize to JSON and verify exact conformance to compose-core schema
        let jsonStr = try frame.toJSONString()
        XCTAssertTrue(jsonStr.contains("\"roll_deg\""))
        XCTAssertTrue(jsonStr.contains("\"pitch_deg\""))
        XCTAssertTrue(jsonStr.contains("\"angular_speed\""))
        XCTAssertTrue(jsonStr.contains("\"is_flatish\""))
        XCTAssertTrue(jsonStr.contains("\"bounds\""))
        XCTAssertTrue(jsonStr.contains("\"joint_type\""))
        XCTAssertTrue(jsonStr.contains("\"point\""))
        XCTAssertTrue(jsonStr.contains("\"mask_summary\""))
        XCTAssertTrue(jsonStr.contains("\"subjects\""))
        XCTAssertTrue(jsonStr.contains("\"camera\""))
        XCTAssertTrue(jsonStr.contains("\"exposure\""))
    }

    func testTieredSchedulingExactCadencesAt60HzAndThermalScaling() {
        let scheduler = PerceptionScheduler()
        var poseCount = 0
        var maskCount = 0
        var faceCount = 0
        var lumaCount = 0

        // 120 frames at 60fps (2.0 seconds)
        for i in 0..<120 {
            let t = Double(i) / 60.0
            let tasks = scheduler.schedule(at: t, thermalState: .nominal, lastPoseHadSubject: false)
            if tasks.runBodyPose { poseCount += 1 }
            if tasks.runSegmentationMask { maskCount += 1 }
            if tasks.runFaceRectangles { faceCount += 1 }
            if tasks.runLumaProbe { lumaCount += 1 }
        }

        // At nominal: 15Hz pose in 2s -> 30, 8Hz mask in 2s -> 15 (every 8 frames in 0..<120), 10Hz face in 2s -> 20, 4Hz luma in 2s -> 8
        XCTAssertEqual(poseCount, 30)
        XCTAssertEqual(maskCount, 15)
        XCTAssertEqual(faceCount, 20)
        XCTAssertEqual(lumaCount, 8)

        // Thermal .serious: rates halved
        scheduler.reset()
        var seriousPose = 0
        var seriousLuma = 0
        for i in 0..<120 {
            let t = Double(i) / 60.0
            let tasks = scheduler.schedule(at: t, thermalState: .serious, lastPoseHadSubject: true)
            if tasks.runBodyPose { seriousPose += 1 }
            if tasks.runLumaProbe { seriousLuma += 1 }
        }
        XCTAssertEqual(seriousPose, 15)
        XCTAssertEqual(seriousLuma, 4)

        // Thermal .critical: mask completely disabled
        scheduler.reset()
        var criticalMask = 0
        for i in 0..<120 {
            let t = Double(i) / 60.0
            let tasks = scheduler.schedule(at: t, thermalState: .critical, lastPoseHadSubject: true)
            if tasks.runSegmentationMask { criticalMask += 1 }
        }
        XCTAssertEqual(criticalMask, 0)
    }

    func testFrameSyncHubLinearMotionInterpolationUnder10ms() {
        let hub = FrameSyncHub()
        let t0 = 1.000
        let t1 = 1.000 + (1.0 / 60.0) // ~1.01667
        hub.pushMotion(MotionReading(timestamp: t0, gravityX: 0.0, gravityY: -1.0, gravityZ: 0.0))
        hub.pushMotion(MotionReading(timestamp: t1, gravityX: 0.10, gravityY: -0.995, gravityZ: 0.0))

        // Query midway: alignment error should be <= 8.4ms (< 10ms SLA)
        let tMid = t0 + (1.0 / 120.0)
        let (interp, errMs, isInterp) = hub.interpolateMotion(at: tMid)

        XCTAssertTrue(isInterp)
        XCTAssertLessThan(errMs, 10.0)
        XCTAssertEqual(interp.gravityX, 0.05, accuracy: 0.005)
    }

    func testFrameSyncHubAttitudeDeltaMotionCompensation() {
        let hub = FrameSyncHub()
        let s = Subject(
            id: 1,
            bounds: NormalizedBox(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
            joints: ["Nose": Joint(joint_type: .Nose, x: 0.5, y: 0.45, confidence: 0.9)],
            facing: "Frontal",
            shot_type: "FullBody",
            confidence: 0.95,
            mask_summary: MaskSummary(top_y: 0.4, bottom_y: 0.6)
        )

        let fromPosture = Posture(roll_deg: 0.0, pitch_deg: 0.0)
        // Pitching up 5 degrees moves the subject lower in the image frame (+dy)
        let toPosture = Posture(roll_deg: 0.0, pitch_deg: 5.0)
        let camera = CameraIntrinsics(focal_length_mm: 24.0, hfov_deg: 73.7)

        let compensated = hub.compensateSubjects([s], fromPosture: fromPosture, toPosture: toPosture, camera: camera)
        XCTAssertEqual(compensated.count, 1)
        let compSubj = compensated[0]

        XCTAssertGreaterThan(compSubj.bounds.y, 0.40)
        XCTAssertGreaterThan(compSubj.joints["Nose"]!.y, 0.45)
        XCTAssertGreaterThan(compSubj.mask_summary!.top_y, 0.40)
    }

    func testLuminanceProbeAndPixelBufferSampling() {
        let w = 64
        let h = 48
        var grid = [UInt8](repeating: 220, count: w * h) // Bright background

        // Dark subject in center
        let subjBox = NormalizedBox(x: 0.3, y: 0.2, width: 0.4, height: 0.5)
        for r in Int(0.2 * Double(h))..<Int(0.7 * Double(h)) {
            for c in Int(0.3 * Double(w))..<Int(0.7 * Double(w)) {
                grid[r * w + c] = 30
            }
        }

        let metrics = PerceptionScheduler.probeLuminance(
            lumaGrid: grid,
            width: w,
            height: h,
            subjectBox: subjBox
        )

        XCTAssertLessThan(metrics.face_to_bg_ratio, 0.45)
        XCTAssertTrue(metrics.is_backlit)
    }

    func testLightContextAndVisionFrameProcessorEndToEnd() throws {
        let processor = VisionFrameProcessor()
        let subj = Subject(
            id: 1,
            bounds: NormalizedBox(x: 0.35, y: 0.2, width: 0.3, height: 0.6),
            joints: ["Nose": Joint(joint_type: .Nose, x: 0.5, y: 0.25, confidence: 0.95)]
        )
        processor.fallbackSubjects = [subj]
        processor.syntheticLumaGrid = (grid: [UInt8](repeating: 150, count: 64 * 48), width: 64, height: 48)

        // Push initial motion so syncHub has valid readings
        processor.syncHub.pushMotion(MotionReading(timestamp: 0.0, gravityX: 0.0, gravityY: -1.0, gravityZ: 0.0))

        let input = PerceptionVideoFrameInput(
            timestamp: 0.0,
            intrinsics: .standardWide,
            exposure: ExposureSummary(iso: 100.0, shutter_speed_sec: 1.0 / 250.0, ev: 11.0)
        )

        let bundle = processor.processFrame(input: input)
        XCTAssertEqual(bundle.frame.subjects.count, 1)
        XCTAssertEqual(bundle.frame.primary_subject_index, 0)
        XCTAssertEqual(bundle.light.ev, 11.0)

        // Validate JSON serialization contains exact compose-core LightContext schema fields
        let lightJson = try bundle.light.toJSONString()
        XCTAssertTrue(lightJson.contains("\"direction\""))
        XCTAssertTrue(lightJson.contains("\"quality\""))
        XCTAssertTrue(lightJson.contains("\"ev\""))
        XCTAssertTrue(lightJson.contains("\"confidence\""))
        XCTAssertTrue(lightJson.contains("\"sun_azimuth_deg\":null"))
        XCTAssertTrue(lightJson.contains("\"sun_elevation_deg\":null"))

        XCTAssertEqual(processor.telemetry.poseExecutionCount, 1)
        XCTAssertEqual(processor.telemetry.lumaExecutionCount, 1)

        // Verify intermediate 60Hz frame preserves t=0.0 subject timestamp and FrameSyncHub applies attitude-delta compensation
        let gz5Deg = sin(5.5 * Double.pi / 180.0)
        let gy5Deg = -sqrt(1.0 - gz5Deg * gz5Deg)
        processor.syncHub.pushMotion(MotionReading(timestamp: 1.0 / 60.0, gravityX: 0.0, gravityY: gy5Deg, gravityZ: gz5Deg))

        let input1 = PerceptionVideoFrameInput(
            timestamp: 1.0 / 60.0,
            intrinsics: .standardWide,
            exposure: ExposureSummary(iso: 100.0, shutter_speed_sec: 1.0 / 250.0, ev: 11.0)
        )
        let bundle1 = processor.processFrame(input: input1)

        // Pose should not re-run on intermediate frame (cadence < 15Hz interval)
        XCTAssertEqual(processor.telemetry.poseExecutionCount, 1)
        XCTAssertEqual(bundle1.frame.subjects.count, 1)

        // Subject box and joints must be compensated downwards due to positive pitch delta
        XCTAssertGreaterThan(bundle1.frame.subjects[0].bounds.y, bundle.frame.subjects[0].bounds.y)
        XCTAssertGreaterThan(bundle1.frame.subjects[0].joints["Nose"]!.point.y, bundle.frame.subjects[0].joints["Nose"]!.point.y)

        // Verify transitioning from body pose to empty body pose + fallbackFaceBoxes triggers 10Hz face fallback
        processor.fallbackSubjects = []
        processor.fallbackFaceBoxes = [NormalizedBox(x: 0.38, y: 0.18, width: 0.24, height: 0.24)]
        processor.syncHub.pushMotion(MotionReading(timestamp: 0.10, gravityX: 0.0, gravityY: -1.0, gravityZ: 0.0))

        let input2 = PerceptionVideoFrameInput(
            timestamp: 0.10,
            intrinsics: .standardWide,
            exposure: ExposureSummary(iso: 100.0, shutter_speed_sec: 1.0 / 250.0, ev: 11.0)
        )
        let bundle2 = processor.processFrame(input: input2)

        XCTAssertEqual(processor.telemetry.poseExecutionCount, 2)
        XCTAssertEqual(processor.telemetry.faceExecutionCount, 1)
        XCTAssertEqual(bundle2.frame.subjects.count, 1)
        XCTAssertEqual(bundle2.frame.subjects[0].bounds.x, 0.26, accuracy: 0.01)

        // Verify subsequent 10Hz face cadence continues to run because lastPoseFoundSubject is decoupled from lastSubjects
        processor.fallbackFaceBoxes = [NormalizedBox(x: 0.40, y: 0.20, width: 0.22, height: 0.22)]
        processor.syncHub.pushMotion(MotionReading(timestamp: 0.20, gravityX: 0.0, gravityY: -1.0, gravityZ: 0.0))

        let input3 = PerceptionVideoFrameInput(
            timestamp: 0.20,
            intrinsics: .standardWide,
            exposure: ExposureSummary(iso: 100.0, shutter_speed_sec: 1.0 / 250.0, ev: 11.0)
        )
        let bundle3 = processor.processFrame(input: input3)

        XCTAssertEqual(processor.telemetry.faceExecutionCount, 2)
        XCTAssertEqual(bundle3.frame.subjects.count, 1)
        XCTAssertEqual(bundle3.frame.subjects[0].bounds.x, 0.29, accuracy: 0.01)

        // Verify clearing face fallback clears stale subjects when body pose remains empty
        processor.fallbackFaceBoxes = []
        processor.syncHub.pushMotion(MotionReading(timestamp: 0.30, gravityX: 0.0, gravityY: -1.0, gravityZ: 0.0))

        let input4 = PerceptionVideoFrameInput(
            timestamp: 0.30,
            intrinsics: .standardWide,
            exposure: ExposureSummary(iso: 100.0, shutter_speed_sec: 1.0 / 250.0, ev: 11.0)
        )
        let bundle4 = processor.processFrame(input: input4)

        XCTAssertEqual(processor.telemetry.faceExecutionCount, 3)
        XCTAssertEqual(bundle4.frame.subjects.count, 0)
    }
}
