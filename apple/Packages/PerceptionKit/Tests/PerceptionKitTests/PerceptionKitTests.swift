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
}
