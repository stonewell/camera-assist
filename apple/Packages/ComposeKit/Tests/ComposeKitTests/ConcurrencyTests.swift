import XCTest
@testable import ComposeKit

final class ConcurrencyTests: XCTestCase {
    func testParallelEvaluationsOnActor() async throws {
        let composer = LiveComposer.createMock()

        try await withThrowingTaskGroup(of: ComposeOutput.self) { group in
            for i in 0..<20 {
                group.addTask {
                    let json = "{\"t\": \(Double(i)), \"posture\": {\"roll_deg\": 0.1, \"pitch_deg\": 0.0, \"elevation_deg\": 0.0}, \"subjects\": []}"
                    return try await composer.evaluate(frameJson: json)
                }
            }

            var count = 0
            for try await result in group {
                XCTAssertTrue(result.isGoodToShoot)
                count += 1
            }
            XCTAssertEqual(count, 20)
        }
    }
}
