import Foundation
import SwiftUI
import ComposeKit

// MARK: - View Models

/// View model representing an analyzed photo in the ReviewApp grid.
public struct ReviewPhotoViewModel: Identifiable, Sendable, Equatable {
    public let id: String
    public let filename: String
    public let originalScore: Int
    public var score: Int
    public var isCulled: Bool
    public var findings: [String]
    public var suggestedFixDescription: String?
    public var suggestedStraightenDeg: Double?
    public var activeAdjustment: AdjustmentPayload?

    public init(
        id: String,
        filename: String,
        score: Int = 100,
        originalScore: Int? = nil,
        isCulled: Bool = false,
        findings: [String] = [],
        suggestedFixDescription: String? = nil,
        suggestedStraightenDeg: Double? = nil,
        activeAdjustment: AdjustmentPayload? = nil
    ) {
        self.id = id
        self.filename = filename
        let initialScore = score
        self.originalScore = originalScore ?? initialScore
        self.score = initialScore
        self.isCulled = isCulled
        self.findings = findings
        self.suggestedFixDescription = suggestedFixDescription
        self.suggestedStraightenDeg = suggestedStraightenDeg
        self.activeAdjustment = activeAdjustment
    }

    public var isGood: Bool {
        score >= 80 && findings.isEmpty
    }

    public var isFixable: Bool {
        suggestedFixDescription != nil || suggestedStraightenDeg != nil
    }
}

/// Aggregated metrics for an album trip or review session.
public struct ReviewTripSummaryViewModel: Sendable, Equatable {
    public let totalPhotos: Int
    public let goodPhotos: Int
    public let culledPhotos: Int
    public let fixablePhotos: Int
    public let averageScore: Double

    public init(
        totalPhotos: Int = 0,
        goodPhotos: Int = 0,
        culledPhotos: Int = 0,
        fixablePhotos: Int = 0,
        averageScore: Double = 0.0
    ) {
        self.totalPhotos = totalPhotos
        self.goodPhotos = goodPhotos
        self.culledPhotos = culledPhotos
        self.fixablePhotos = fixablePhotos
        self.averageScore = averageScore
    }
}

// MARK: - Photo Review Coordinator

/// Coordinates album scanning, still frame composition analysis via ComposeKit LiveComposer,
/// interactive culling, and batch non-destructive auto-fix application.
@MainActor
public final class PhotoReviewCoordinator: ObservableObject {
    @Published public var photos: [ReviewPhotoViewModel] = []
    @Published public var selectedPhotoId: String? = nil
    @Published public var tripSummary: ReviewTripSummaryViewModel = ReviewTripSummaryViewModel()
    @Published public var isAnalyzing: Bool = false

    public let composer: LiveComposer?
    public let adjustmentStore: NonDestructiveAdjustmentStore

    public init(
        composer: LiveComposer? = nil,
        adjustmentStore: NonDestructiveAdjustmentStore = .shared
    ) {
        self.composer = composer
        self.adjustmentStore = adjustmentStore
    }

    /// Evaluates a still frame capture via `LiveComposer.analyzeStill` bypassing temporal hysteresis.
    public func analyzeStillFrame(
        photoId: String,
        frameJson: String,
        lightJson: String? = nil
    ) async -> [ComposeFinding] {
        guard let composer = self.composer else { return [] }
        do {
            let findings = try await composer.analyzeStill(frameJson: frameJson, lightJson: lightJson)
            return findings
        } catch {
            return []
        }
    }

    /// Toggles culling status for a photo (marking it for deletion / archiving).
    public func toggleCull(for photoId: String) {
        guard let idx = photos.firstIndex(where: { $0.id == photoId }) else { return }
        photos[idx].isCulled.toggle()
        updateSummary()
    }

    /// Previews or applies an auto-fix recipe (e.g. horizon straightening or auto-crop).
    public func previewAutoFix(for photoId: String) {
        guard let idx = photos.firstIndex(where: { $0.id == photoId }) else { return }
        let photo = photos[idx]
        guard let angle = photo.suggestedStraightenDeg else { return }

        let payload = AdjustmentPayload(straightenAngleDeg: angle)
        applyAdjustment(for: photoId, payload: payload)
    }

    /// Applies a non-destructive adjustment payload and updates the persistent adjustment store.
    public func applyAdjustment(for photoId: String, payload: AdjustmentPayload) {
        adjustmentStore.saveAdjustment(for: photoId, payload: payload)
        if let idx = photos.firstIndex(where: { $0.id == photoId }) {
            photos[idx].activeAdjustment = payload
            photos[idx].score = min(100, photos[idx].originalScore + 15)
        }
        updateSummary()
    }

    /// Reverts any non-destructive adjustment for a photo.
    public func revertAdjustment(for photoId: String) {
        adjustmentStore.revertAdjustment(for: photoId)
        if let idx = photos.firstIndex(where: { $0.id == photoId }) {
            photos[idx].activeAdjustment = nil
            photos[idx].score = photos[idx].originalScore
        }
        updateSummary()
    }

    /// Batch applies all suggested auto-fixes across all unculled fixable photos in the session.
    public func batchApplyAllAutoFixes() {
        for idx in 0..<photos.lenSafe {
            if !photos[idx].isCulled, let angle = photos[idx].suggestedStraightenDeg {
                let payload = AdjustmentPayload(straightenAngleDeg: angle)
                adjustmentStore.saveAdjustment(for: photos[idx].id, payload: payload)
                photos[idx].activeAdjustment = payload
                photos[idx].score = min(100, photos[idx].originalScore + 15)
            }
        }
        updateSummary()
    }

    /// Recalculates summary metrics for the active session.
    public func updateSummary() {
        let total = photos.count
        guard total > 0 else {
            tripSummary = ReviewTripSummaryViewModel()
            return
        }

        var good = 0
        var culled = 0
        var fixable = 0
        var scoreSum = 0

        for p in photos {
            if p.isGood { good += 1 }
            if p.isCulled { culled += 1 }
            if p.isFixable { fixable += 1 }
            scoreSum += p.score
        }

        tripSummary = ReviewTripSummaryViewModel(
            totalPhotos: total,
            goodPhotos: good,
            culledPhotos: culled,
            fixablePhotos: fixable,
            averageScore: Double(scoreSum) / Double(total)
        )
    }
}

private extension Array {
    var lenSafe: Int { count }
}
