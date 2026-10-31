import Foundation

/// Errors surfaced by the ComposeKit wrapper.
///
/// TASK-01: there is no silent mock fallback any more. Because the generated
/// `compose_ffi.swift` references the native `compose-ffi` C symbols directly, ComposeKit
/// cannot even compile without the linked `ComposeCore.xcframework`. This error therefore
/// covers runtime failures that survive linking (e.g. a malformed config); callers must
/// never swallow it.
public enum ComposeEngineError: Error, LocalizedError, Sendable {
    case initializationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .initializationFailed(let reason):
            return """
            ComposeEngine unavailable: \(reason). \
            This is a runtime failure — a missing ComposeCore.xcframework would have failed \
            at compile time instead. Build it with ./scripts/build-xcframework.sh.
            """
        }
    }
}

/// High-level actor providing thread-safe, non-blocking composition rule evaluation.
/// Complies with Swift 6 strict concurrency standards.
public actor LiveComposer {
    private var engine: LiveEngine?
    /// `false` in every release build. Mock engines exist only under `#if DEBUG`, and a
    /// missing native engine throws instead of degrading to mock.
    public private(set) var isMockMode: Bool = false
    private var focusRuleId: String? = nil

    /// Initialize LiveComposer with optional JSON config and backend name.
    ///
    /// Throws `ComposeEngineError.initializationFailed` when the Rust engine is not
    /// available. Callers must not swallow this error.
    public init(configJson: String = "{}", backend: String = "vision") throws {
        do {
            self.engine = try LiveEngine(configJson: configJson, backend: backend)
            self.isMockMode = false
        } catch {
            self.engine = nil
            self.isMockMode = false
            throw ComposeEngineError.initializationFailed("\(error)")
        }
    }

    #if DEBUG
    /// Debug-only mock engine (SwiftUI previews). Never compiled into release builds.
    private init(mockMode: Bool) {
        self.engine = nil
        self.isMockMode = mockMode
    }

    /// Explicitly enable mock mode for UI previews and unit tests without native binary.
    public static func createMock() -> LiveComposer {
        return LiveComposer(mockMode: true)
    }
    #endif

    /// Process a frame through the Rust composition engine.
    ///
    /// Throws `ComposeEngineError.initializationFailed("engine not initialized")` when the
    /// engine is missing or mock, so a caller can never mistake mock output for a real
    /// evaluation.
    public func evaluate(
        frameJson: String,
        lightJson: String? = nil,
        timestamp: Double = 0.0
    ) throws -> ComposeOutput {
        guard let eng = self.engine, !self.isMockMode else {
            throw ComposeEngineError.initializationFailed("engine not initialized")
        }
        let ffiOut = try eng.stepJson(frameJson: frameJson, lightJson: lightJson, t: timestamp)
        return ComposeOutput(
            activeFindingId: ffiOut.activeFindingId,
            hintKey: ffiOut.hintKey,
            isGoodToShoot: ffiOut.isGoodToShoot,
            rawFindingsCount: Int(ffiOut.rawFindingsCount)
        )
    }

    /// Set prioritized focus rule.
    public func setFocusRule(id: String?) {
        self.focusRuleId = id
        self.engine?.setFocus(ruleId: id)
    }

    /// Get engine version.
    ///
    /// Returns `"0.0.0-unlinked"` when the native engine is absent — never a fake version.
    public func version() -> String {
        return self.engine?.version() ?? "0.0.0-unlinked"
    }
}
