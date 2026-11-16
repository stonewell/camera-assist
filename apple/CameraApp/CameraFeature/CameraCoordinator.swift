import Foundation
import SwiftUI
import CoreGraphics

#if canImport(AVFoundation)
import AVFoundation
#endif

#if canImport(Photos)
import Photos
#endif

import CaptureKit
import PerceptionKit
import ComposeKit

/// Preset camera zoom steps mapped to lens types and default pinhole camera intrinsics.
public enum CameraZoomPreset: String, CaseIterable, Identifiable, Sendable {
    case ultraWide = "0.5x"
    case wide = "1x"
    case tele2x = "2x"
    case tele3x = "3x"

    public var id: String { rawValue }
    public var title: String { rawValue }

    public var lensType: CameraLensType {
        switch self {
        case .ultraWide:
            return .ultraWide
        case .wide:
            return .wide
        case .tele2x:
            return .telephoto2x
        case .tele3x:
            return .telephoto
        }
    }

    public var defaultIntrinsics: CameraIntrinsics {
        switch self {
        case .ultraWide:
            return CameraIntrinsics(focal_length_mm: 13.0, hfov_deg: 120.0)
        case .wide:
            return CameraIntrinsics(focal_length_mm: 24.0, hfov_deg: 84.0)
        case .tele2x:
            return CameraIntrinsics(focal_length_mm: 48.0, hfov_deg: 48.0)
        case .tele3x:
            return CameraIntrinsics(focal_length_mm: 77.0, hfov_deg: 32.0)
        }
    }
}

/// Snapshot of an evaluated frame including telemetry, composition finding, rendered joints, and SLA validation.
public struct FrameEvaluationSnapshot: Sendable {
    public let telemetry: DebugTelemetry
    public let composeOutput: ComposeOutput
    public let renderJoints: [String: RenderJoint]
    public let primaryBoundingBox: CGRect?
    public let isWithinLatencySLA: Bool

    public init(
        telemetry: DebugTelemetry,
        composeOutput: ComposeOutput,
        renderJoints: [String: RenderJoint] = [:],
        primaryBoundingBox: CGRect? = nil,
        isWithinLatencySLA: Bool = true
    ) {
        self.telemetry = telemetry
        self.composeOutput = composeOutput
        self.renderJoints = renderJoints
        self.primaryBoundingBox = primaryBoundingBox
        self.isWithinLatencySLA = isWithinLatencySLA
    }
}

/// Central coordinator for CameraApp unifying CaptureKit (AVFoundation 24MP session),
/// PerceptionKit (Vision pose, linear motion interpolation, tiered scheduling),
/// and ComposeKit (LiveComposer rule evaluation within < 1.0ms SLA).
@MainActor
public final class CameraCoordinator: ObservableObject {
    public let sessionManager: CaptureSessionManager
    public let photoController: CapturePhotoController
    public var rotationBridge: RotationCoordinatorBridge { sessionManager.rotationBridge }
    public let attitudeTracker: AttitudeTracker
    public let syncHub: FrameSyncHub
    public let perceptionScheduler: PerceptionScheduler
    public let bodyPoseAnalyzer: BodyPoseAnalyzer
    public let visionProcessor: VisionFrameProcessor
    public let composer: LiveComposer?

    public let engineLatencySLACeilingMs: Double = 1.0

    public let hintResolver: HintCatalogResolver = .shared
    public let hapticEngine: GuidanceHapticEngine = GuidanceHapticEngine()
    public let voicePrompter: VoicePrompter

    @Published public var isVoiceEnabled: Bool = true
    @Published public var lastQuickLaunchRequest: CameraQuickLaunchRequest? = nil

    @Published public var telemetry: DebugTelemetry = DebugTelemetry()
    @Published public var renderJoints: [String: RenderJoint] = [:]
    @Published public var primaryBoundingBox: CGRect? = nil
    @Published public var activeFinding: String? = nil
    @Published public var activeHintBannerText: String = "构图不错，可以拍"
    @Published public var isGoodToShoot: Bool = true
    @Published public var isFlatish: Bool = false
    @Published public var currentZoomPreset: CameraZoomPreset = .wide
    @Published public var isDebugHUDVisible: Bool = true
    @Published public var isCapturing: Bool = false
    @Published public var lastCapturedPhoto: PhotoCaptureResult? = nil
    @Published public var engineLatencyMs: Double = 0.0
    @Published public var isSessionRunning: Bool = false

    @Published public var latestComposeOutput: ComposeOutput = ComposeOutput(isGoodToShoot: true)
    @Published public var activeHint: ComposeHint = ComposeHint(primary: "构图不错，可以拍", secondary: "", spoken: "好，拍吧")
    @Published public var isUserGuidanceEnabled: Bool = true
    @Published public var hintLocale: String = "zh-Hans"

    private var isProcessingFrame: Bool = false
    private var latestProcessedTimestamp: Double = -.infinity
    private nonisolated(unsafe) var quickLaunchObserver: (any NSObjectProtocol)? = nil

    public init(
        sessionManager: CaptureSessionManager = CaptureSessionManager(),
        photoController: CapturePhotoController = CapturePhotoController(),
        attitudeTracker: AttitudeTracker = AttitudeTracker(),
        syncHub: FrameSyncHub? = nil,
        perceptionScheduler: PerceptionScheduler = PerceptionScheduler(),
        bodyPoseAnalyzer: BodyPoseAnalyzer = BodyPoseAnalyzer(),
        visionProcessor: VisionFrameProcessor? = nil,
        composer: LiveComposer? = nil,
        voicePrompter: VoicePrompter? = nil
    ) {
        self.sessionManager = sessionManager
        self.photoController = photoController
        self.attitudeTracker = attitudeTracker
        let resolvedVoicePrompter = voicePrompter ?? VoicePrompter()
        self.voicePrompter = resolvedVoicePrompter
        self.isVoiceEnabled = resolvedVoicePrompter.isEnabled

        let resolvedSyncHub = syncHub ?? FrameSyncHub(attitudeTracker: attitudeTracker)
        self.syncHub = resolvedSyncHub

        self.perceptionScheduler = perceptionScheduler
        self.bodyPoseAnalyzer = bodyPoseAnalyzer

        let vp = visionProcessor ?? VisionFrameProcessor(
            scheduler: perceptionScheduler,
            poseAnalyzer: bodyPoseAnalyzer,
            syncHub: resolvedSyncHub
        )
        self.visionProcessor = vp

        var resolvedComposer = composer
        if resolvedComposer == nil {
            #if DEBUG
            resolvedComposer = (try? LiveComposer(configJson: "{}", backend: "vision")) ?? LiveComposer.createMock()
            #else
            resolvedComposer = try? LiveComposer(configJson: "{}", backend: "vision")
            #endif
        }
        self.composer = resolvedComposer

        setupFramePipeline()
        setupRotationBridge()
        setupQuickLaunchObserver()
    }

    deinit {
        if let observer = quickLaunchObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupQuickLaunchObserver() {
        self.quickLaunchObserver = NotificationCenter.default.addObserver(
            forName: .cameraAssistQuickLaunchRequested,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let req = (notification.userInfo?["request"] as? CameraQuickLaunchRequest)
                ?? (notification.object as? CameraQuickLaunchRequest)
            guard let req else { return }
            Task { @MainActor [weak self] in
                self?.applyQuickLaunchRequest(req)
            }
        }
    }

    /// Toggles voice prompt speech guidance.
    public func toggleVoice() {
        isVoiceEnabled.toggle()
        voicePrompter.isEnabled = isVoiceEnabled
    }

    /// Sets explicit voice prompt speech enabled/disabled state.
    public func setVoiceEnabled(_ enabled: Bool) {
        isVoiceEnabled = enabled
        voicePrompter.isEnabled = enabled
    }

    /// Handles deep link URLs (e.g. `camera-assist://launch?mode=live`).
    @discardableResult
    public func handleDeepLink(_ url: URL) -> Bool {
        guard let request = CameraQuickLaunchRequest.parse(url: url) else { return false }
        applyQuickLaunchRequest(request)
        return true
    }

    /// Applies incoming quick launch request configurations (mode, zoom preset).
    public func applyQuickLaunchRequest(_ request: CameraQuickLaunchRequest) {
        self.lastQuickLaunchRequest = request

        if let zoomStr = request.zoomPreset, let preset = CameraZoomPreset(rawValue: zoomStr) {
            Task {
                await self.selectZoomPreset(preset)
            }
        }

        switch request.mode {
        case .live:
            self.isUserGuidanceEnabled = true
        case .normal:
            self.isUserGuidanceEnabled = false
        case .stranger:
            self.isUserGuidanceEnabled = true
        }
    }

    private func setupRotationBridge() {
        sessionManager.rotationBridge.onAnglesChanged = { [weak attitudeTracker, weak photoController] angles in
            attitudeTracker?.captureAngleDeg = angles.captureAngleDeg
            photoController?.captureAngle = angles.captureAngleDeg
        }
    }

    private func setupFramePipeline() {
        sessionManager.setFrameHandler { [weak self] frame in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                guard !self.isProcessingFrame else { return }
                await self.processIncomingSample(frame)
            }
        }
    }

    /// Starts motion tracking and the AVFoundation capture session.
    public func start() async {
        attitudeTracker.startTracking { [weak syncHub] reading in
            syncHub?.pushMotion(reading)
        }
        do {
            try await sessionManager.startSession()
            self.isSessionRunning = sessionManager.isRunning
        } catch {
            // Graceful handling for simulator / non-AV hosts
        }
    }

    /// Stops motion tracking and the capture session.
    public func stop() async {
        voicePrompter.stopSpeakingImmediate()
        attitudeTracker.stopTracking()
        await sessionManager.stopSession()
        self.isSessionRunning = sessionManager.isRunning
    }

    /// Switches optical/digital zoom lens preset (0.5x, 1x, 2x, 3x).
    public func selectZoomPreset(_ preset: CameraZoomPreset) async {
        self.currentZoomPreset = preset
        do {
            try await sessionManager.switchLens(to: preset.lensType)
        } catch {
            // Handle lens switch error
        }
    }

    /// Maps recommended continuous/discrete zoom factor to nearest discrete CameraZoomPreset.
    public func applyRecommendedZoom(factor: Float) async {
        if factor <= 0.7 {
            await selectZoomPreset(.ultraWide)
        } else if factor <= 1.4 {
            await selectZoomPreset(.wide)
        } else if factor <= 2.4 {
            await selectZoomPreset(.tele2x)
        } else {
            await selectZoomPreset(.tele3x)
        }
    }

    /// Updates focus and exposure at normalized device coordinate.
    public func focusAndExpose(at devicePoint: CGPoint) async {
        await sessionManager.focusAndExpose(at: devicePoint)
    }

    /// Captures a 24MP still photograph using Apple's computational imaging pipeline,
    /// requesting PhotoKit authorization when appropriate and saving with sandbox fallback.
    public func capturePhoto() async -> PhotoCaptureResult? {
        guard !isCapturing else { return nil }
        self.isCapturing = true
        voicePrompter.notifyCaptureStarted()
        defer {
            self.isCapturing = false
            voicePrompter.notifyCaptureEnded()
        }

        #if canImport(Photos)
        if PHPhotoLibrary.authorizationStatus(for: .addOnly) == .notDetermined {
            await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        #endif

        let captureAngle = sessionManager.rotationBridge.currentAngles.captureAngleDeg
        let orientation = sessionManager.rotationBridge.visionOrientation

        do {
            #if canImport(AVFoundation)
            let result = try await photoController.capturePhoto(
                from: sessionManager.photoOutput,
                captureAngle: captureAngle,
                orientation: orientation
            )
            #else
            let result = try await photoController.capturePhoto(
                from: nil,
                captureAngle: captureAngle,
                orientation: orientation
            )
            #endif
            self.lastCapturedPhoto = result
            return result
        } catch {
            return nil
        }
    }

    /// Processes a single incoming video sample frame through Vision perception and LiveComposer rules.
    public func processIncomingSample(_ frame: VideoSampleFrame) async {
        guard !isProcessingFrame else { return }
        guard frame.presentationTimestamp >= latestProcessedTimestamp else { return }
        isProcessingFrame = true
        latestProcessedTimestamp = frame.presentationTimestamp
        defer { isProcessingFrame = false }

        let intrinsics = CameraIntrinsics.from(
            focalLengthMm: frame.focalLengthMm ?? currentZoomPreset.defaultIntrinsics.focal_length_mm,
            hfovDeg: frame.hfovDeg ?? (frame.intrinsicMatrix == nil ? currentZoomPreset.defaultIntrinsics.hfov_deg : nil),
            intrinsicMatrix: frame.intrinsicMatrix,
            imageWidth: Float(frame.width)
        )

        let exposure = ExposureSummary.from(
            iso: frame.iso ?? 100.0,
            shutterSpeedSeconds: Float(frame.shutterSpeedSeconds ?? (1.0 / 60.0)),
            lensAperture: frame.lensAperture ?? 1.8,
            exposureBias: frame.exposureBias ?? 0.0,
            evOverride: frame.ev
        )

        #if canImport(CoreVideo)
        let input = PerceptionVideoFrameInput(
            timestamp: frame.presentationTimestamp,
            pixelBuffer: frame.pixelBuffer,
            intrinsics: intrinsics,
            exposure: exposure,
            orientation: frame.orientation
        )
        #else
        let input = PerceptionVideoFrameInput(
            timestamp: frame.presentationTimestamp,
            intrinsics: intrinsics,
            exposure: exposure,
            orientation: frame.orientation
        )
        #endif

        let bundle = visionProcessor.processFrame(input: input)

        // Map skeletal joints & primary bounding box for rendering
        var mappedJoints: [String: RenderJoint] = [:]
        var primaryBox: CGRect? = nil
        if let primarySubject = bundle.frame.subjects.first {
            primaryBox = CGRect(
                x: CGFloat(primarySubject.bounds.x),
                y: CGFloat(primarySubject.bounds.y),
                width: CGFloat(primarySubject.bounds.width),
                height: CGFloat(primarySubject.bounds.height)
            )
            for (key, joint) in primarySubject.joints {
                mappedJoints[key] = RenderJoint(
                    id: key,
                    x: CGFloat(joint.point.x),
                    y: CGFloat(joint.point.y),
                    confidence: joint.confidence
                )
            }
        }
        self.renderJoints = mappedJoints
        self.primaryBoundingBox = primaryBox

        // Evaluate composition rules via LiveComposer
        guard let frameJson = try? bundle.frame.toJSONString() else { return }
        let lightJson = try? bundle.light.toJSONString()

        var output: ComposeOutput? = nil
        var evalLatency: Double = 0.0

        if let comp = self.composer, await !comp.isMockMode {
            let start = CFAbsoluteTimeGetCurrent()
            do {
                output = try await comp.evaluate(
                    frameJson: frameJson,
                    lightJson: lightJson,
                    timestamp: frame.presentationTimestamp
                )
            } catch {
                output = nil
            }
            evalLatency = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
        } else {
            output = ComposeOutput(
                activeFindingId: nil,
                severity: .good,
                hintKey: "good",
                hintText: "构图不错，可以拍",
                isGoodToShoot: true,
                rawFindingsCount: 0
            )
            evalLatency = 0.4
        }

        let resolvedOutput = output ?? ComposeOutput(
            activeFindingId: nil,
            severity: .good,
            hintKey: "good",
            hintText: "构图不错，可以拍",
            isGoodToShoot: true,
            rawFindingsCount: 0
        )

        self.engineLatencyMs = evalLatency
        self.isGoodToShoot = resolvedOutput.isGoodToShoot
        self.isFlatish = bundle.frame.posture.is_flatish
        self.activeFinding = resolvedOutput.activeFindingId
        self.latestComposeOutput = resolvedOutput

        let resolvedHint = hintResolver.resolve(
            hintKey: resolvedOutput.hintKey,
            locale: hintLocale,
            fallbackHint: resolvedOutput.hint
        )
        self.activeHint = resolvedHint

        if !resolvedHint.primary.isEmpty {
            self.activeHintBannerText = resolvedHint.primary
        } else if resolvedOutput.isGoodToShoot {
            self.activeHintBannerText = "构图不错，可以拍"
        } else {
            self.activeHintBannerText = "调整相机角度"
        }

        hapticEngine.evaluateTransition(
            isGoodToShoot: resolvedOutput.isGoodToShoot,
            rollDeg: Double(bundle.frame.posture.roll_deg),
            pitchDeg: Double(bundle.frame.posture.pitch_deg),
            isFlatish: bundle.frame.posture.is_flatish
        )

        _ = voicePrompter.evaluateAndSpeak(
            output: resolvedOutput,
            isCapturingPhoto: isCapturing,
            timestamp: CFAbsoluteTimeGetCurrent()
        )

        self.telemetry = DebugTelemetry(
            fps: Double(sessionManager.effectiveFrameRate),
            latencyMs: evalLatency,
            rollDeg: Double(bundle.frame.posture.roll_deg),
            pitchDeg: Double(bundle.frame.posture.pitch_deg),
            activeFindingId: resolvedOutput.activeFindingId,
            hintKey: resolvedOutput.hintKey ?? (resolvedOutput.isGoodToShoot ? "good" : "adjust"),
            thermalState: sessionManager.currentThermalState.rawValue,
            subjectCount: bundle.frame.subjects.count
        )
    }
}
