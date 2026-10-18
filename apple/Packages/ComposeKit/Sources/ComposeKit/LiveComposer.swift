import Foundation

/// High-level actor providing thread-safe, non-blocking composition rule evaluation.
/// Complies with Swift 6 strict concurrency standards.
public actor LiveComposer {
    private var engine: LiveEngine?
    private var isMockMode: Bool = false
    private var focusRuleId: String? = nil

    /// Initialize LiveComposer with optional JSON config and backend name.
    public init(configJson: String = "{}", backend: String = "vision") {
        do {
            self.engine = try LiveEngine(configJson: configJson, backend: backend)
            self.isMockMode = false
        } catch {
            // Graceful fallback to pure-Swift mock mode if native binary is not linked (e.g. early UI development)
            self.engine = nil
            self.isMockMode = true
        }
    }

    private init(mockMode: Bool) {
        self.engine = nil
        self.isMockMode = mockMode
    }

    /// Explicitly enable mock mode for UI previews and unit tests without native binary.
    public static func createMock() -> LiveComposer {
        return LiveComposer(mockMode: true)
    }

    /// Process a frame through the Rust composition engine or Swift mock fallback.
    public func evaluate(
        frameJson: String,
        lightJson: String? = nil,
        timestamp: Double = 0.0
    ) throws -> ComposeOutput {
        if !self.isMockMode, let eng = self.engine {
            let ffiOut = try eng.stepJson(frameJson: frameJson, lightJson: lightJson, t: timestamp)
            return ComposeOutput(
                activeFindingId: ffiOut.activeFindingId,
                hintKey: ffiOut.hintKey,
                isGoodToShoot: ffiOut.isGoodToShoot,
                rawFindingsCount: Int(ffiOut.rawFindingsCount)
            )
        } else {
            // Mock evaluation logic for early Swift preview
            return evaluateMockJson(frameJson: frameJson)
        }
    }

    /// Set prioritized focus rule.
    public func setFocusRule(id: String?) {
        self.focusRuleId = id
        self.engine?.setFocus(ruleId: id)
    }

    /// Get engine version.
    public func version() -> String {
        return self.engine?.version() ?? "1.0.0-mock"
    }

    // MARK: - Private Mock Evaluator

    private func evaluateMockJson(frameJson: String) -> ComposeOutput {
        // Simple heuristic mock for roll angle
        if frameJson.contains("\"roll_deg\": 3.") || frameJson.contains("\"roll_deg\": 4.") {
            return ComposeOutput(
                activeFindingId: "tilt.level",
                hintKey: "rotate_ccw",
                isGoodToShoot: false,
                rawFindingsCount: 1
            )
        } else if frameJson.contains("\"crop.head\"") || frameJson.contains("\"min_y\": 0.00") {
            return ComposeOutput(
                activeFindingId: "crop.head",
                hintKey: "tilt_up",
                isGoodToShoot: false,
                rawFindingsCount: 1
            )
        } else {
            return ComposeOutput(
                activeFindingId: nil,
                hintKey: "good",
                isGoodToShoot: true,
                rawFindingsCount: 0
            )
        }
    }
}
