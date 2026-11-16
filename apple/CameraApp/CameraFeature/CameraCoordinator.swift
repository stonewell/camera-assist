import Foundation
import SwiftUI
import CoreGraphics
import ImageIO

#if canImport(AVFoundation)
import AVFoundation
#else
public enum AVAuthorizationStatus: Int, Sendable {
    case notDetermined = 0
    case restricted = 1
    case denied = 2
    case authorized = 3
}
#endif

#if canImport(Photos)
import Photos
#else
public enum PHAuthorizationStatus: Int, Sendable {
    case notDetermined = 0
    case restricted = 1
    case denied = 2
    case authorized = 3
    case limited = 4
}
#endif

#if canImport(UIKit)
import UIKit
#endif

#if canImport(CoreImage)
import CoreImage
#endif

import CaptureKit
import PerceptionKit
import ComposeKit
import SyncKit

// MARK: - Banner Models (TASK-14)

/// Severity levels for in-app floating banner messages.
public enum CameraBannerSeverity: String, Sendable, Equatable {
    case info
    case warning
    case critical
}

/// Floating non-blocking banner notification model for camera runtime feedback.
public struct CameraBannerMessage: Identifiable, Sendable, Equatable {
    public enum ActionType: String, Sendable, Equatable {
        case openSettings
        case dismiss
        case retry
        case retrySessionStart
        case retryCapture
        case retrySendStrangerReference
        case retrySaveStrangerCapture
    }

    public typealias BannerActionType = ActionType

    public let id: UUID
    public let title: String
    public let message: String
    public let severity: CameraBannerSeverity
    public let actionTitle: String?
    public let actionType: ActionType?
    public let timestamp: Double

    public init(
        id: UUID = UUID(),
        title: String,
        message: String,
        severity: CameraBannerSeverity = .info,
        actionTitle: String? = nil,
        actionType: ActionType? = nil,
        timestamp: Double = CFAbsoluteTimeGetCurrent()
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.severity = severity
        self.actionTitle = actionTitle
        self.actionType = actionType
        self.timestamp = timestamp
    }
}

// MARK: - Camera Self-Timer (TASK-18)

/// Self-timer duration choices for camera shutter capture.
public enum CameraTimerDuration: Int, Sendable, CaseIterable, Equatable {
    case off = 0
    case threeSeconds = 3
    case tenSeconds = 10
}

// MARK: - Camera Zoom Preset

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

/// Visual framing overlay box for detected subjects in the camera viewfinder.
public struct SubjectOverlayBox: Identifiable, Equatable, Sendable {
    public let id: String
    public let rect: CGRect
    public let isPrimary: Bool

    public init(id: String, rect: CGRect, isPrimary: Bool) {
        self.id = id
        self.rect = rect
        self.isPrimary = isPrimary
    }
}

/// Central coordinator for CameraApp unifying CaptureKit (AVFoundation 24MP session),
/// PerceptionKit (Vision pose, linear motion interpolation, tiered scheduling),
/// ComposeKit (LiveComposer rule evaluation within < 1.0ms SLA), and SyncKit (Stranger Assist).
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
    @Published public var subjectBoxes: [SubjectOverlayBox] = []
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

    // Regular Camera Controls (TASK-18)
    @Published public var flashMode: CaptureFlashMode = .auto
    @Published public var exposureBias: Float = 0.0
    @Published public var isEVSliderVisible: Bool = false
    @Published public var isGridVisible: Bool = false
    @Published public var timerDuration: CameraTimerDuration = .off
    @Published public var countdownRemaining: Int? = nil
    @Published public var latestThumbnailData: Data? = nil
    @Published public var isThumbnailPreviewPresented: Bool = false

    @Published public var latestComposeOutput: ComposeOutput = ComposeOutput(isGoodToShoot: true)
    @Published public var activeHint: ComposeHint = ComposeHint(primary: "构图不错，可以拍", secondary: "", spoken: "好，拍吧")
    @Published public var isUserGuidanceEnabled: Bool = true
    @Published public var hintLocale: String = "zh-Hans"

    // Permissions & Banner state (TASK-14)
    @Published public var cameraPermissionStatus: AVAuthorizationStatus = .notDetermined
    @Published public var photoPermissionStatus: PHAuthorizationStatus = .notDetermined
    @Published public var activeBanner: CameraBannerMessage? = nil
    @Published public var isEngineDegraded: Bool = false
    @Published public var engineDegradeReason: String? = nil

    // Stranger Assist state (TASK-15)
    @Published public var isStrangerAssistPresented: Bool = false
    @Published public var strangerSessionId: UUID? = nil
    @Published public var strangerShortCode: String = ""
    @Published public var strangerUniversalLink: URL? = nil
    @Published public var strangerSessionRemainingSeconds: Int = 600
    @Published public var strangerSyncStatus: SyncStatus = .pending
    @Published public var receivedStrangerCapture: CapturePackage? = nil
    @Published public var isStrangerReviewPresented: Bool = false
    @Published public var isSendingReference: Bool = false
    @Published public var isWaitingForCapture: Bool = false
    @Published public var isStrangerOfflineP2PEnabled: Bool = true
    public private(set) var strangerSyncSession: SyncSession? = nil

    private var isProcessingFrame: Bool = false
    private var latestProcessedTimestamp: Double = -.infinity
    private nonisolated(unsafe) var quickLaunchObserver: (any NSObjectProtocol)? = nil

    private var consecutiveEvalFailures: Int = 0
    private var consecutiveHighLatencyFrames: Int = 0

    private var activeStrangerSession: SyncSession? {
        get { strangerSyncSession }
        set { strangerSyncSession = newValue }
    }
    private var activeStrangerKey: Data? = nil
    private var activeStrangerToken: SessionToken? = nil
    private var strangerStartTask: Task<Void, Never>? = nil
    private var strangerTimer: Task<Void, Never>? = nil
    private var captureWaitTask: Task<Void, Never>? = nil
    private var countdownTask: Task<Void, Never>? = nil

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

        // Evaluate initial engine degradation state
        if self.composer == nil {
            self.isEngineDegraded = true
            self.engineDegradeReason = "构图引擎未初始化"
        } else {
            self.isEngineDegraded = false
            self.engineDegradeReason = nil
        }

        setupFramePipeline()
        setupRotationBridge()
        setupQuickLaunchObserver()
        setupRuntimeErrorHandling()
    }

    deinit {
        if let observer = quickLaunchObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        countdownTask?.cancel()
        strangerStartTask?.cancel()
        strangerTimer?.cancel()
        captureWaitTask?.cancel()
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

    private func setupRuntimeErrorHandling() {
        sessionManager.onRuntimeError = { [weak self] error in
            Task { @MainActor [weak self] in
                self?.handleSessionRuntimeError(error)
            }
        }
    }

    private func handleSessionRuntimeError(_ error: CaptureSessionRuntimeError) {
        switch error {
        case .hardwareInUseByAnotherClient(let msg):
            postBanner(
                title: "相机硬件被占用",
                message: "相机硬件已被其他应用占用: \(msg)",
                severity: .warning,
                actionTitle: "重试",
                actionType: .retrySessionStart
            )
        case .audioInterruption(let msg):
            postBanner(
                title: "音频中断",
                message: "音频输入中断: \(msg)",
                severity: .info,
                actionTitle: "忽略",
                actionType: .dismiss
            )
        case .backgroundSessionInterrupted(let msg):
            postBanner(
                title: "后台运行中断",
                message: "后台运行导致相机断开: \(msg)",
                severity: .warning,
                actionTitle: "恢复",
                actionType: .retrySessionStart
            )
        case .multiAppInterrupted(let msg):
            postBanner(
                title: "多任务模式中断",
                message: "多前台应用导致相机不可用: \(msg)",
                severity: .warning,
                actionTitle: "重试",
                actionType: .retrySessionStart
            )
        case .sessionRuntimeFailure(let msg):
            postBanner(
                title: "相机运行异常",
                message: "相机运行时异常: \(msg)",
                severity: .critical,
                actionTitle: "重试",
                actionType: .retrySessionStart
            )
        }
    }

    // MARK: - Banner Actions (TASK-14)

    /// Posts an active floating banner toast.
    public func postBanner(
        title: String,
        message: String,
        severity: CameraBannerSeverity = .info,
        actionTitle: String? = nil,
        actionType: CameraBannerMessage.ActionType? = nil
    ) {
        self.activeBanner = CameraBannerMessage(
            title: title,
            message: message,
            severity: severity,
            actionTitle: actionTitle,
            actionType: actionType
        )
    }

    /// Dismisses the currently visible banner toast.
    public func dismissBanner() {
        self.activeBanner = nil
    }

    /// Handles actions triggered from banner buttons.
    public func handleBannerAction(_ action: CameraBannerMessage.ActionType) {
        switch action {
        case .openSettings:
            #if canImport(UIKit)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
            #endif
            dismissBanner()
        case .dismiss:
            dismissBanner()
        case .retrySessionStart:
            dismissBanner()
            Task {
                await start()
            }
        case .retryCapture:
            dismissBanner()
            Task {
                _ = await capturePhoto()
            }
        case .retrySendStrangerReference:
            dismissBanner()
            Task {
                await sendStrangerReferencePackage()
            }
        case .retrySaveStrangerCapture:
            dismissBanner()
            confirmStrangerCaptureAndSave()
        case .retry:
            dismissBanner()
            Task {
                await start()
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
        #if canImport(AVFoundation)
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        self.cameraPermissionStatus = status
        if status == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            self.cameraPermissionStatus = granted ? .authorized : .denied
        }
        guard self.cameraPermissionStatus == .authorized else {
            return
        }
        #else
        self.cameraPermissionStatus = .authorized
        #endif

        fetchLatestPhotoThumbnail()

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
        cancelCountdown()
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
    public func focusAndExpose(at devicePoint: CGPoint) {
        sessionManager.focusAndExpose(at: devicePoint)
    }

    // MARK: - Regular Camera Controls (TASK-18)

    /// Cycles through flash modes: auto -> on -> off -> auto.
    public func cycleFlashMode() {
        switch flashMode {
        case .auto:
            flashMode = .on
        case .on:
            flashMode = .off
        case .off:
            flashMode = .auto
        }
    }

    /// Sets camera exposure compensation bias, clamped to -2.0...2.0 EV.
    public func setExposureBias(_ ev: Float) {
        let clamped = max(-2.0, min(ev, 2.0))
        self.exposureBias = clamped
        sessionManager.setExposureBias(clamped)
    }

    /// Toggles the exposure bias slider visibility.
    public func toggleEVSlider() {
        isEVSliderVisible.toggle()
    }

    /// Toggles the 3x3 rule-of-thirds composition grid visibility.
    public func toggleGrid() {
        isGridVisible.toggle()
    }

    /// Cycles self-timer duration: off (0s) -> 3s -> 10s -> off.
    public func cycleTimerDuration() {
        switch timerDuration {
        case .off:
            timerDuration = .threeSeconds
        case .threeSeconds:
            timerDuration = .tenSeconds
        case .tenSeconds:
            timerDuration = .off
        }
    }

    /// Cancels active self-timer countdown if in progress.
    public func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        countdownRemaining = nil
    }

    /// Triggers immediate photo capture (if timer is off) or initiates 1Hz countdown.
    /// If countdown is currently running, cancels it.
    public func triggerShutter() {
        guard !isCapturing else { return }
        if countdownRemaining != nil || countdownTask != nil {
            cancelCountdown()
            return
        }

        if timerDuration == .off {
            Task {
                _ = await capturePhoto()
            }
        } else {
            // Cancel any previous countdown task before starting a new one
            cancelCountdown()

            let total = timerDuration.rawValue
            countdownRemaining = total
            countdownTask = Task { @MainActor [weak self] in
                guard let self = self else { return }
                defer {
                    self.countdownTask = nil
                    self.countdownRemaining = nil
                }
                for sec in stride(from: total, through: 1, by: -1) {
                    guard !Task.isCancelled else { return }
                    self.countdownRemaining = sec
                    do {
                        try await Task.sleep(nanoseconds: 1_000_000_000)
                    } catch {
                        return
                    }
                    guard !Task.isCancelled else { return }
                }
                guard !Task.isCancelled else { return }
                self.countdownRemaining = nil
                self.countdownTask = nil
                _ = await self.capturePhoto()
            }
        }
    }

    /// Fetches the latest photo thumbnail from the user's photo library.
    public func fetchLatestPhotoThumbnail() {
        #if canImport(Photos)
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            return
        }
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 1
        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        guard let asset = fetchResult.firstObject else { return }

        let imageManager = PHImageManager.default()
        let requestOptions = PHImageRequestOptions()
        requestOptions.isSynchronous = false
        requestOptions.deliveryMode = .fastFormat
        requestOptions.isNetworkAccessAllowed = false

        let targetSize = CGSize(width: 120, height: 120)
        imageManager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: requestOptions) { [weak self] image, _ in
            #if canImport(UIKit)
            if let uiImage = image, let jpegData = uiImage.jpegData(compressionQuality: 0.7) {
                Task { @MainActor [weak self] in
                    self?.latestThumbnailData = jpegData
                }
            }
            #endif
        }
        #endif
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
        var photoStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if photoStatus == .notDetermined {
            photoStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        self.photoPermissionStatus = photoStatus
        if photoStatus == .denied || photoStatus == .restricted {
            postBanner(
                title: "相册权限受限",
                message: "未获得相册保存权限，无法存储拍摄照片",
                severity: .warning,
                actionTitle: "前往设置",
                actionType: .openSettings
            )
            return nil
        }
        #else
        self.photoPermissionStatus = .authorized
        #endif

        let captureAngle = sessionManager.rotationBridge.currentAngles.captureAngleDeg
        let orientation = sessionManager.rotationBridge.visionOrientation

        do {
            #if canImport(AVFoundation)
            let result = try await photoController.capturePhoto(
                from: sessionManager.photoOutput,
                captureAngle: captureAngle,
                orientation: orientation,
                flashMode: flashMode
            )
            #else
            let result = try await photoController.capturePhoto(
                from: nil,
                captureAngle: captureAngle,
                orientation: orientation,
                flashMode: flashMode
            )
            #endif
            self.lastCapturedPhoto = result
            if let data = result.rawData {
                self.latestThumbnailData = data
            }
            fetchLatestPhotoThumbnail()
            return result
        } catch CapturePhotoError.timeout {
            postBanner(
                title: "拍摄超时",
                message: "24MP 深度图像计算超时，请稍后重试",
                severity: .warning,
                actionTitle: "重试",
                actionType: .retryCapture
            )
            return nil
        } catch CapturePhotoError.storageFull {
            postBanner(
                title: "存储空间不足",
                message: "设备可用存储空间不足，无法保存高质量照片",
                severity: .critical,
                actionTitle: "前往设置",
                actionType: .openSettings
            )
            return nil
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

        // Map skeletal joints & subject bounding boxes for rendering
        var mappedJoints: [String: RenderJoint] = [:]
        var primaryBox: CGRect? = nil
        var mappedBoxes: [SubjectOverlayBox] = []

        let primaryIndex = bundle.frame.primary_subject_index ?? 0

        for (idx, subject) in bundle.frame.subjects.enumerated() {
            let isPrimary = (idx == primaryIndex) || (idx == 0 && bundle.frame.primary_subject_index == nil)
            let boxRect = CGRect(
                x: CGFloat(subject.bounds.x),
                y: CGFloat(subject.bounds.y),
                width: CGFloat(subject.bounds.width),
                height: CGFloat(subject.bounds.height)
            )
            mappedBoxes.append(SubjectOverlayBox(
                id: "\(subject.id)",
                rect: boxRect,
                isPrimary: isPrimary
            ))

            if isPrimary {
                primaryBox = boxRect
                for (key, joint) in subject.joints {
                    mappedJoints[key] = RenderJoint(
                        id: key,
                        x: CGFloat(joint.point.x),
                        y: CGFloat(joint.point.y),
                        confidence: joint.confidence
                    )
                }
            }
        }

        if primaryBox == nil, let firstBox = mappedBoxes.first {
            primaryBox = firstBox.rect
        }

        self.renderJoints = mappedJoints
        self.primaryBoundingBox = primaryBox
        self.subjectBoxes = mappedBoxes

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

        // Engine Degradation Evaluation (TASK-14)
        var isMock = false
        if let comp = self.composer {
            isMock = await comp.isMockMode
        }

        if self.composer == nil {
            self.isEngineDegraded = true
            self.engineDegradeReason = "构图引擎未初始化"
        } else if isMock {
            self.isEngineDegraded = true
            self.engineDegradeReason = "构图引擎运行于Mock模式"
        } else if output == nil {
            consecutiveEvalFailures += 1
            if consecutiveEvalFailures >= 3 {
                self.isEngineDegraded = true
                self.engineDegradeReason = "构图引擎连续求值失败(>=3帧)"
            }
        } else {
            consecutiveEvalFailures = 0
            if evalLatency > 5.0 {
                consecutiveHighLatencyFrames += 1
            } else {
                consecutiveHighLatencyFrames = 0
            }

            if consecutiveHighLatencyFrames >= 30 {
                self.isEngineDegraded = true
                self.engineDegradeReason = "构图引擎计算超时(持续30帧>5.0ms)"
            } else if sessionManager.effectiveFrameRate < 15 {
                self.isEngineDegraded = true
                self.engineDegradeReason = "相机采样帧率过低(<15 FPS)"
            } else {
                self.isEngineDegraded = false
                self.engineDegradeReason = nil
            }
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

    // MARK: - Stranger Assist Orchestration (TASK-15)

    /// Opens the stranger assist sheet and ensures an active ephemeral session exists.
    public func openStrangerAssist() {
        self.isStrangerAssistPresented = true
        if strangerSyncSession == nil || strangerSessionRemainingSeconds <= 0 {
            startStrangerAssistSession()
        }
    }

    /// Generates a fresh ephemeral 10-minute session, 32-byte E2EE key, 6-char short code,
    /// HMAC-signed token, Universal Link (#k=...), and starts the 10-minute countdown timer.
    public func startStrangerAssistSession() {
        let previousSession = self.strangerSyncSession
        strangerStartTask?.cancel()
        captureWaitTask?.cancel()
        strangerTimer?.cancel()
        if let prev = previousSession {
            Task {
                await prev.close()
            }
        }

        let sessionId = UUID()
        let sessionKey = URLFragmentKey.generateRandomKey()
        let shortCode = String(sessionId.uuidString.replacingOccurrences(of: "-", with: "").prefix(6)).uppercased()

        let token = SessionToken.generate(
            sessionId: sessionId,
            role: .guest,
            ttlSeconds: 600.0,
            secret: sessionKey
        )

        let baseURL = URL(string: "https://clip.camera-assist.app/assist")!
        let universalLink = URLFragmentKey.buildUniversalLink(
            baseURL: baseURL,
            sessionId: sessionId,
            token: token.toTokenString(),
            key: sessionKey,
            isOfflineMode: isStrangerOfflineP2PEnabled
        )

        var relayComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        relayComponents?.scheme = "wss"
        let relayURL = relayComponents?.url ?? baseURL
        let transport = FallbackSyncTransport(
            primary: WebSocketTransport(url: relayURL),
            fallback: BonjourTransport(mode: .listener(serviceType: BonjourTransport.defaultServiceType)),
            preferLocalOnly: isStrangerOfflineP2PEnabled
        )

        let session = SyncSession(
            sessionId: sessionId,
            role: .owner,
            transport: transport,
            sessionKey: sessionKey,
            ttlSeconds: 600.0
        )

        self.strangerSyncSession = session
        self.activeStrangerKey = sessionKey
        self.activeStrangerToken = token
        self.strangerSessionId = sessionId
        self.strangerShortCode = shortCode
        self.strangerUniversalLink = universalLink
        self.strangerSessionRemainingSeconds = 600
        self.strangerSyncStatus = .pending
        self.receivedStrangerCapture = nil

        // Start connection and handshake phase in background Task
        self.strangerStartTask = Task { @MainActor [weak self] in
            do {
                try await session.start(token: token, secretForTokenVerification: sessionKey)
                guard !Task.isCancelled else { return }
                self?.strangerSyncStatus = .ready
            } catch {
                guard !Task.isCancelled else { return }
                self?.strangerSyncStatus = .failed
            }
        }

        // 10-minute countdown timer
        self.strangerTimer = Task { @MainActor [weak self] in
            while let self = self, self.strangerSessionRemainingSeconds > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { break }
                self.strangerSessionRemainingSeconds -= 1
                if self.strangerSessionRemainingSeconds <= 0 {
                    self.strangerSyncStatus = .expired
                    break
                }
            }
        }
    }

    /// Cancels active tasks and closes the ephemeral stranger assist session.
    public func closeStrangerAssistSession() {
        let session = self.strangerSyncSession
        strangerStartTask?.cancel()
        captureWaitTask?.cancel()
        strangerTimer?.cancel()
        if let s = session {
            Task {
                await s.close()
            }
        }
        self.strangerSyncStatus = .completed
        self.isStrangerAssistPresented = false
    }

    /// Builds a ReferencePackage containing framing, angle, zoom factor, roll, pitch,
    /// thumbnail, and prompt key, sends it via SyncSession to the guest device, and starts waiting for capture.
    public func sendStrangerReferencePackage() async {
        guard let session = strangerSyncSession else {
            startStrangerAssistSession()
            guard let retrySession = strangerSyncSession else { return }
            await sendStrangerReferencePackageInternal(session: retrySession)
            return
        }

        if session.status == .pending || session.status == .connecting || strangerSyncStatus == .pending || strangerSyncStatus == .connecting {
            if let startTask = strangerStartTask {
                _ = await withTaskGroup(of: Void.self) { group in
                    group.addTask {
                        _ = await startTask.result
                    }
                    group.addTask {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                    }
                    _ = await group.next()
                }
            }

            if session.status != .ready && strangerSyncStatus != .ready {
                postBanner(
                    title: "等待路人连接",
                    message: "路人尚未扫描二维码或会话正在建立连接，请稍候连接就绪后重试",
                    severity: .info,
                    actionTitle: "好的",
                    actionType: .dismiss
                )
                return
            }
        }

        if session.status == .failed || strangerSyncStatus == .failed {
            postBanner(
                title: "连接失败",
                message: "帮拍连接失败，请点击刷新口令重新连接",
                severity: .warning,
                actionTitle: "刷新",
                actionType: .retrySessionStart
            )
            return
        }

        if session.status == .expired || strangerSyncStatus == .expired {
            postBanner(
                title: "口令已过期",
                message: "帮拍口令已过期，请刷新口令",
                severity: .warning,
                actionTitle: "刷新",
                actionType: .retrySessionStart
            )
            return
        }

        await sendStrangerReferencePackageInternal(session: session)
    }

    private func sendStrangerReferencePackageInternal(session: SyncSession) async {
        self.isSendingReference = true
        defer { self.isSendingReference = false }

        let targetFraming: NormalizedRect
        if let box = primaryBoundingBox {
            targetFraming = NormalizedRect(
                x: Float(box.origin.x),
                y: Float(box.origin.y),
                width: Float(box.size.width),
                height: Float(box.size.height)
            )
        } else {
            targetFraming = NormalizedRect(x: 0.15, y: 0.15, width: 0.7, height: 0.7)
        }

        let roll = telemetry.rollDeg
        let pitch = telemetry.pitchDeg
        let angle = sessionManager.rotationBridge.currentAngles.captureAngleDeg

        let zoomFactor: Double
        switch currentZoomPreset {
        case .ultraWide: zoomFactor = 0.5
        case .wide: zoomFactor = 1.0
        case .tele2x: zoomFactor = 2.0
        case .tele3x: zoomFactor = 3.0
        }

        let package = ReferencePackage(
            sessionId: session.sessionId,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(Double(strangerSessionRemainingSeconds)),
            ownerDeviceToken: "owner",
            promptKey: activeHint.primary,
            targetFraming: targetFraming,
            compositionType: "portrait",
            thumbnailJpegData: lastCapturedPhoto?.rawData,
            targetZoomFactor: zoomFactor,
            captureAngle: angle,
            elevationDeg: pitch,
            rollDeg: roll,
            slots: [],
            languageCode: hintLocale
        )

        do {
            try await session.sendReferencePackage(package)
            self.strangerSyncStatus = .syncing
            self.waitForStrangerCapture()
        } catch {
            self.strangerSyncStatus = .failed
            self.postBanner(
                title: "构图参考发送失败",
                message: "无法发送构图参考至帮拍设备，请重试",
                severity: .warning,
                actionTitle: "重试",
                actionType: .retrySendStrangerReference
            )
        }
    }

    /// Waits for incoming encrypted CapturePackage from the guest device, decrypts it, and triggers review.
    public func waitForStrangerCapture() {
        captureWaitTask?.cancel()
        self.isWaitingForCapture = true
        self.captureWaitTask = Task { @MainActor [weak self] in
            guard let self = self, let session = self.strangerSyncSession else { return }
            do {
                let capture = try await session.receiveCapturePackage()
                guard !Task.isCancelled else { return }
                self.receivedStrangerCapture = capture
                self.strangerSyncStatus = .captured
                self.isWaitingForCapture = false
                self.isStrangerReviewPresented = true
            } catch {
                guard !Task.isCancelled else { return }
                self.isWaitingForCapture = false
                if self.strangerSyncStatus != .completed {
                    self.strangerSyncStatus = .failed
                }
            }
        }
    }

    /// Confirms stranger capture review, saves returned 24MP photo data to Photos library,
    /// sends statusUpdate(.completed) ACK over transport, and posts confirmation banner.
    public func confirmStrangerCaptureAndSave() {
        guard let capture = receivedStrangerCapture else { return }
        let photoData = capture.fullPhotoData

        #if canImport(Photos)
        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: photoData, options: nil)
        }) { [weak self] success, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if success {
                    self.postBanner(
                        title: "照片已保存",
                        message: "路人帮拍的 24MP 照片已成功保存至系统相册",
                        severity: .info,
                        actionTitle: "好的",
                        actionType: .dismiss
                    )
                } else {
                    self.postBanner(
                        title: "保存失败",
                        message: "未能将照片保存至相册: \(error?.localizedDescription ?? "未知错误")",
                        severity: .warning,
                        actionTitle: "重试",
                        actionType: .retrySaveStrangerCapture
                    )
                }
            }
        }
        #else
        postBanner(
            title: "照片已保存",
            message: "路人帮拍照片保存成功 (模拟)",
            severity: .info,
            actionTitle: "好的",
            actionType: .dismiss
        )
        #endif

        strangerStartTask?.cancel()
        captureWaitTask?.cancel()
        strangerTimer?.cancel()
        Task {
            if let session = strangerSyncSession {
                try? await session.transport.send(message: .statusUpdate(.completed))
                await session.close()
            }
        }

        self.isStrangerReviewPresented = false
        self.isStrangerAssistPresented = false
        self.strangerSyncStatus = .completed
    }
}
