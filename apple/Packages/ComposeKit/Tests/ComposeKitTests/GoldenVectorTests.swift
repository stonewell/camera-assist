import XCTest
@testable import ComposeKit

/// Runs every fixture under `fixtures/golden/*.json` through the real Rust engine.
///
/// TASK-01: these tests require the linked `ComposeCore.xcframework` (see
/// `scripts/build-xcframework.sh`). A mock engine is explicitly rejected: if
/// `LiveComposer.isMockMode` is true, or the native engine is unlinked, the test fails.
final class GoldenVectorTests: XCTestCase {
    var composer: LiveComposer!

    /// `apple/Packages/ComposeKit/Tests/ComposeKitTests/GoldenVectorTests.swift`
    /// -> six parent hops reach the repository root.
    private static var repoRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            url.deleteLastPathComponent()
        }
        return url
    }

    private var goldenDir: URL {
        Self.repoRoot.appendingPathComponent("fixtures/golden", isDirectory: true)
    }

    override func setUp() async throws {
        try await super.setUp()
        self.composer = try LiveComposer(configJson: "{}", backend: "vision")
        let composer = try XCTUnwrap(self.composer)
        let isMock = await composer.isMockMode
        XCTAssertFalse(isMock, "Native compose-ffi engine must be linked; mock mode is forbidden")
    }

    func testEngineVersionIsReal() async throws {
        let composer = try XCTUnwrap(self.composer)
        let isMock = await composer.isMockMode
        XCTAssertFalse(isMock, "Mock engine must never be used for golden vectors")
        let version = await composer.version()
        XCTAssertEqual(version, "0.1.0")
    }

    func testAllGoldenVectorsMatchRustEngine() async throws {
        let files = try FileManager.default
            .contentsOfDirectory(at: goldenDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != "schema.json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        XCTAssertEqual(files.count, 13, "Expected 13 golden vectors in \(goldenDir.path)")
        XCTAssertFalse(files.isEmpty)

        for file in files {
            let data = try Data(contentsOf: file)
            let root = try XCTUnwrap(
                try JSONSerialization.jsonObject(with: data) as? [String: Any],
                "\(file.lastPathComponent): fixture root must be a JSON object"
            )
            let vectorId = try XCTUnwrap(root["id"] as? String, "\(file.lastPathComponent): missing id")
            let input = try XCTUnwrap(
                root["input"] as? [String: Any],
                "\(vectorId): missing input"
            )
            let frame = try XCTUnwrap(input["frame"] as? [String: Any], "\(vectorId): missing input.frame")
            let expected = try XCTUnwrap(
                root["expected_findings"] as? [[String: Any]],
                "\(vectorId): missing expected_findings"
            )

            // Fresh composer per vector: the Rust arbiter keeps temporal state
            // (enter_delay / exit_hold / snooze), so sharing one actor across vectors
            // would leak hints from a previous fixture into the next assertion.
            let composer = try LiveComposer(configJson: "{}", backend: "vision")

            let isMock = await composer.isMockMode
            XCTAssertFalse(isMock, "\(vectorId): native compose-ffi engine must be linked, mock is forbidden")
            let version = await composer.version()
            XCTAssertEqual(version, "0.1.0", "\(vectorId): unexpected engine version")

            // Re-serialise the fixture fragments so the test exercises the same JSON
            // boundary the app uses (no hand-written payloads).
            let frameJson = try jsonString(from: frame)
            let lightJson = try (input["light"] as? [String: Any]).map { try jsonString(from: $0) }

            let output = try await composer.evaluate(frameJson: frameJson, lightJson: lightJson)

            let isMockAfterEvaluate = await composer.isMockMode
            XCTAssertFalse(isMockAfterEvaluate, "\(vectorId): engine degraded to mock mode")

            if expected.isEmpty {
                XCTAssertEqual(output.rawFindingsCount, 0, "\(vectorId): expected no findings")
                XCTAssertTrue(output.isGoodToShoot, "\(vectorId): expected good-to-shoot")
            } else {
                // The FFI output exposes the arbitrated top finding plus the raw count, not the
                // full finding set (the Rust golden_runner owns exact-set parity, TASK-02).
                XCTAssertGreaterThanOrEqual(
                    output.rawFindingsCount,
                    expected.count,
                    "\(vectorId): expected findings were not all triggered"
                )
                XCTAssertNotNil(output.activeFindingId, "\(vectorId): expected an active finding")
                XCTAssertNotNil(output.hintKey, "\(vectorId): expected a hint key")
                XCTAssertFalse(output.isGoodToShoot, "\(vectorId): a finding was expected")

                // When the engine surfaces exactly one finding there is no arbitration
                // ambiguity left, so the expected id/hint must match exactly.
                if output.rawFindingsCount == 1, expected.count == 1 {
                    let finding = expected[0]
                    XCTAssertEqual(
                        output.activeFindingId,
                        finding["id"] as? String,
                        "\(vectorId): activeFindingId mismatch"
                    )
                    XCTAssertEqual(
                        output.hintKey,
                        finding["hint_key"] as? String,
                        "\(vectorId): hintKey mismatch"
                    )
                }
            }
        }
    }

    private func jsonString(from object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [])
        return try XCTUnwrap(String(data: data, encoding: .utf8), "Failed to re-encode fixture JSON")
    }
}
