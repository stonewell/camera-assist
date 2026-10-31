import XCTest
@testable import ComposeKit

final class ConcurrencyTests: XCTestCase {
    func testParallelEvaluationsOnActor() async throws {
        // TASK-01: the real engine is mandatory here; mock mode is not acceptable.
        let composer = try LiveComposer(configJson: "{}", backend: "vision")
        let isMock = await composer.isMockMode
        XCTAssertFalse(isMock, "Native compose-ffi engine must be linked; mock mode is forbidden")

        // Same shape as fixtures/golden/010_good_to_shoot_fullbody.json (complete Frame JSON:
        // camera / exposure / primary_subject_index present, zero expected findings).
        let frameJson: @Sendable (Double) -> String = { t in
            return """
            {
              "t": \(t),
              "subjects": [
                {
                  "id": 1,
                  "bounds": { "x": 0.35, "y": 0.12, "width": 0.30, "height": 0.80 },
                  "joints": {
                    "Nose": {
                      "joint_type": "Nose",
                      "point": { "x": 0.50, "y": 0.20 },
                      "confidence": 0.95
                    }
                  },
                  "facing": "Frontal",
                  "shot_type": "FullBody",
                  "confidence": 0.98,
                  "mask_summary": null
                }
              ],
              "primary_subject_index": 0,
              "posture": {
                "roll_deg": 0.2,
                "pitch_deg": -1.5,
                "elevation_deg": -1.5
              },
              "camera": {
                "focal_length_mm": 24.0,
                "hfov_deg": 73.7
              },
              "exposure": {
                "iso": 100.0,
                "shutter_speed_sec": 0.002,
                "ev": 12.0
              }
            }
            """
        }

        try await withThrowingTaskGroup(of: ComposeOutput.self) { group in
            for i in 0..<20 {
                group.addTask {
                    return try await composer.evaluate(frameJson: frameJson(Double(i)))
                }
            }

            var count = 0
            for try await result in group {
                XCTAssertTrue(result.isGoodToShoot)
                XCTAssertEqual(result.rawFindingsCount, 0)
                count += 1
            }
            XCTAssertEqual(count, 20)
        }
    }
}
