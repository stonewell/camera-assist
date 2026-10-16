import XCTest
@testable import ComposeKit

final class GoldenVectorTests: XCTestCase {
    var composer: LiveComposer!

    override func setUp() async throws {
        try await super.setUp()
        self.composer = LiveComposer.createMock()
    }

    func testLevelPhoneGoldenVector() async throws {
        let frameJson = """
        {
            "t": 1.0,
            "posture": { "roll_deg": 3.5, "pitch_deg": 0.0, "elevation_deg": 0.0 },
            "subjects": []
        }
        """

        let output = try await composer.evaluate(frameJson: frameJson)
        XCTAssertEqual(output.activeFindingId, "tilt.level")
        XCTAssertEqual(output.hintKey, "rotate_ccw")
        XCTAssertFalse(output.isGoodToShoot)
    }

    func testGoodToShootFullBodyGoldenVector() async throws {
        let frameJson = """
        {
            "t": 10.0,
            "posture": { "roll_deg": 0.2, "pitch_deg": -1.5, "elevation_deg": -1.5 },
            "subjects": []
        }
        """

        let output = try await composer.evaluate(frameJson: frameJson)
        XCTAssertNil(output.activeFindingId)
        XCTAssertEqual(output.hintKey, "good")
        XCTAssertTrue(output.isGoodToShoot)
    }
}
