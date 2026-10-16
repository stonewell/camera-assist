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
    }

    func testBodyPoseAnalyzerNormalization() {
        let analyzer = BodyPoseAnalyzer(minConfidence: 0.3)
        let rawKeypoints: [String: (point: CGPoint, confidence: Float)] = [
            "nose": (point: CGPoint(x: 0.5, y: 0.8), confidence: 0.95), // Vision bottom-left: y=0.8 is near top
            "lAnkle": (point: CGPoint(x: 0.4, y: 0.1), confidence: 0.85),
            "rWrist": (point: CGPoint(x: 0.7, y: 0.5), confidence: 0.15) // Below threshold -> should be filtered
        ]

        let joints = analyzer.processKeypoints(rawKeypoints, timestamp: 1.0)
        XCTAssertEqual(joints.count, 2)
        XCTAssertNil(joints["rWrist"])

        // Nose in Vision (x=0.5, y=0.8) -> top-left UI should have y = 1.0 - 0.8 = 0.2
        let nose = joints["nose"]!
        XCTAssertEqual(nose.x, 0.5, accuracy: 0.01)
        XCTAssertEqual(nose.y, 0.2, accuracy: 0.01)
        XCTAssertEqual(nose.confidence, 0.95, accuracy: 0.001)
    }

    func testMaskSummarizerTouchDetection() {
        let bbox = NormalizedBox(min_x: 0.005, min_y: 0.01, max_x: 0.8, max_y: 0.99)
        let summary = MaskSummarizer.summarize(bbox: bbox)

        XCTAssertTrue(summary.touches_top)
        XCTAssertTrue(summary.touches_left)
        XCTAssertTrue(summary.touches_bottom)
        XCTAssertFalse(summary.touches_right)
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

        // Push detected subjects
        let s1 = Subject(
            id: "person_1",
            bbox: NormalizedBox(min_x: 0.25, min_y: 0.15, max_x: 0.75, max_y: 0.85),
            joints: ["nose": Joint(x: 0.5, y: 0.2, confidence: 0.9)],
            mask: MaskSummary(top_y: 0.15)
        )
        hub.updateSubjects([s1])

        // Assemble frame at video timestamp 10.018
        let frame = hub.assembleFrame(timestamp: 10.018)
        XCTAssertEqual(frame.t, 10.018)
        XCTAssertEqual(frame.subjects.count, 1)
        XCTAssertEqual(frame.primary_subject_index, 0)

        // Serialize to JSON and verify conformance to compose-core schema
        let jsonStr = try frame.toJSONString()
        XCTAssertTrue(jsonStr.contains("\"roll_deg\""))
        XCTAssertTrue(jsonStr.contains("\"pitch_deg\""))
        XCTAssertTrue(jsonStr.contains("\"subjects\""))
        XCTAssertTrue(jsonStr.contains("\"camera\""))
        XCTAssertTrue(jsonStr.contains("\"exposure\""))
    }
}
