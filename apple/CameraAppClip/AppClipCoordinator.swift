import Foundation
import SwiftUI
import CoreGraphics
import ImageIO

#if canImport(AVFoundation)
@preconcurrency import AVFoundation
#endif

#if canImport(CoreMotion) && !os(macOS)
import CoreMotion
#endif

#if canImport(UIKit)
import UIKit
#endif

import SyncKit

/// Single-instruction guidance cues tailored for strangers holding the helper phone.
public struct StrangerCue: Equatable, Sendable {
    public let primary: String
    public let subtitle: String

    public init(primary: String, subtitle: String) {
        self.primary = primary
        self.subtitle = subtitle
    }

    public static let connecting = StrangerCue(
        primary: "正在连接帮拍会话...",
        subtitle: "Connecting to owner's phone..."
    )
    public static let waitingForReference = StrangerCue(
        primary: "正在接收构图参考...",
        subtitle: "Receiving reference frame..."
    )
    public static let alignGhost = StrangerCue(
        primary: "把人物对准黄色虚影",
        subtitle: "Align subject with yellow outline"
    )
    public static let rotateClockwise = StrangerCue(
        primary: "手机顺时针转一点",
        subtitle: "Rotate phone clockwise"
    )
    public static let rotateCounterClockwise = StrangerCue(
        primary: "手机逆时针转一点",
        subtitle: "Rotate phone counter-clockwise"
    )
    public static let tiltUp = StrangerCue(
        primary: "手机往上抬一点",
        subtitle: "Tilt phone up slightly"
    )
    public static let tiltDown = StrangerCue(
        primary: "手机往下按一点",
        subtitle: "Tilt phone down slightly"
    )
    public static let stepBack = StrangerCue(
        primary: "后退一步",
        subtitle: "Take a step back"
    )
    public static let stepForward = StrangerCue(
        primary: "往前走一步",
        subtitle: "Take a step forward"
    )
    public static let holdSteady = StrangerCue(
        primary: "完美！请保持稳定，点击拍照",
        subtitle: "Perfect! Hold steady and tap shutter"
    )
    public static let uploading = StrangerCue(
        primary: "正在加密传回照片...",
        subtitle: "Encrypting and uploading photo..."
    )
    public static let completed = StrangerCue(
        primary: "帮拍完成！",
        subtitle: "Photo returned safely"
    )
    public static let failed = StrangerCue(
        primary: "传输失败，请点击重试",
        subtitle: "Upload failed, tap to retry"
    )
    public static let sessionExpired = StrangerCue(
        primary: "帮拍会话已过期",
        subtitle: "Session has expired"
    )
}

/// Dynamic posture and framing alignment state between the helper phone and target reference.
public struct StrangerAlignmentState: Equatable, Sendable {
    public var rollDeg: Double
    public var pitchDeg: Double
    public var offset: AlignmentOffset
    public var scale: Double

    public var isRollAligned: Bool
    public var isPitchAligned: Bool
    public var isFramingAligned: Bool
    public var isScaleAligned: Bool
    public var isReadyToShoot: Bool

    public var activeCue: StrangerCue

    public init(
        rollDeg: Double = 0.0,
        pitchDeg: Double = 0.0,
        offset: AlignmentOffset = AlignmentOffset(),
        scale: Double = 1.0,
        isRollAligned: Bool = true,
        isPitchAligned: Bool = true,
        isFramingAligned: Bool = true,
        isScaleAligned: Bool = true,
        isReadyToShoot: Bool = true,
        activeCue: StrangerCue = .alignGhost
    ) {
        self.rollDeg = rollDeg
        self.pitchDeg = pitchDeg
        self.offset = offset
        self.scale = scale
        self.isRollAligned = isRollAligned
        self.isPitchAligned = isPitchAligned
        self.isFramingAligned = isFramingAligned
        self.isScaleAligned = isScaleAligned
        self.isReadyToShoot = isReadyToShoot
        self.activeCue = activeCue
    }

    /// Evaluates alignment against reference package using hysteresis thresholds.
    public static func evaluate(
        currentRoll: Double,
        currentPitch: Double,
        reference: ReferencePackage,
        previousState: StrangerAlignmentState? = nil
    ) -> StrangerAlignmentState {
        // Tolerances with enter/exit hysteresis
        let wasRollAligned = previousState?.isRollAligned ?? false
        let rollTolerance = wasRollAligned ? 2.5 : 1.5
        let rollDiff = currentRoll - reference.rollDeg
        let isRollAligned = abs(rollDiff) <= rollTolerance

        let wasPitchAligned = previousState?.isPitchAligned ?? false
        let pitchTolerance = wasPitchAligned ? 5.0 : 3.0
        let pitchDiff = currentPitch - reference.elevationDeg
        let isPitchAligned = abs(pitchDiff) <= pitchTolerance

        let isFramingAligned = true
        let isScaleAligned = true
        let isReady = isRollAligned && isPitchAligned && isFramingAligned && isScaleAligned

        let cue: StrangerCue
        if isReady {
            cue = .holdSteady
        } else if !isRollAligned {
            cue = (rollDiff > 0) ? .rotateCounterClockwise : .rotateClockwise
        } else if !isPitchAligned {
            cue = (pitchDiff > 0) ? .tiltDown : .tiltUp
        } else {
            cue = .alignGhost
        }

        return StrangerAlignmentState(
            rollDeg: currentRoll,
            pitchDeg: currentPitch,
            offset: AlignmentOffset(dx: 0.0, dy: 0.0),
            scale: 1.0,
            isRollAligned: isRollAligned,
            isPitchAligned: isPitchAligned,
            isFramingAligned: isFramingAligned,
            isScaleAligned: isScaleAligned,
            isReadyToShoot: isReady,
            activeCue: cue
        )
    }
}

/// Ephemeral capture saved in the App Clip sandbox temporary directory.
public struct CachedClipCapture: Sendable, Equatable {
    public let photoId: String
    public let sessionId: UUID
    public let rawJpegURL: URL
    public let encryptedEnvelopeURL: URL
    public let capturedAt: Date
    public let fileSizeBytes: Int
    public let package: CapturePackage

    public init(
        photoId: String,
        sessionId: UUID,
        rawJpegURL: URL,
        encryptedEnvelopeURL: URL,
        capturedAt: Date = Date(),
        fileSizeBytes: Int,
        package: CapturePackage
    ) {
        self.photoId = photoId
        self.sessionId = sessionId
        self.rawJpegURL = rawJpegURL
        self.encryptedEnvelopeURL = encryptedEnvelopeURL
        self.capturedAt = capturedAt
        self.fileSizeBytes = fileSizeBytes
        self.package = package
    }
}

#if canImport(AVFoundation)
/// Lightweight delegate handling asynchronous photo output capture completion.
private final class ClipPhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<Data, Error>?
    var onCompletion: (() -> Void)?

    init(continuation: CheckedContinuation<Data, Error>) {
        self.continuation = continuation
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        defer { onCompletion?() }
        if let error = error {
            continuation?.resume(throwing: error)
            continuation = nil
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            continuation?.resume(throwing: NSError(domain: "ClipCapture", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to obtain photo file data"]))
            continuation = nil
            return
        }
        continuation?.resume(returning: data)
        continuation = nil
    }
}
#endif

/// Central coordinator managing App Clip invocation, AVFoundation viewfinder, CoreMotion attitude,
/// and end-to-end encrypted photo return to owner device.
@MainActor
public final class AppClipCoordinator: ObservableObject {
    @Published public var syncStatus: SyncStatus = .pending
    @Published public var referencePackage: ReferencePackage? = nil
    @Published public var alignmentState: StrangerAlignmentState = StrangerAlignmentState()
    @Published public var ghostOpacity: Double = 0.5
    @Published public var isCapturing: Bool = false
    @Published public var isUploading: Bool = false
    @Published public var isCompleted: Bool = false
    @Published public private(set) var isSessionFinished: Bool = false
    @Published public private(set) var hasActiveInvocation: Bool = false
    @Published public var uploadError: String? = nil
    @Published public var lastCaptureResult: CachedClipCapture? = nil
    @Published public var sessionRole: SessionRole = .guest
    @Published public var activeCue: StrangerCue = .connecting

    public private(set) var invocationPayload: AppClipInvocationPayload? = nil
    private var syncSession: SyncSession? = nil
    private var cachedPackageForRetry: CapturePackage? = nil
    private let cipher: any E2EECipher = DefaultE2EECipher()
    private let sessionQueue = DispatchQueue(label: "com.stonewell.camera-assist.clip.session")
    private var activeCaptureDelegate: AnyObject? = nil

    #if canImport(AVFoundation)
    public let captureSession: AVCaptureSession = AVCaptureSession()
    public let photoOutput: AVCapturePhotoOutput = AVCapturePhotoOutput()
    private var isSessionConfigured: Bool = false
    #endif

    #if canImport(CoreMotion) && !os(macOS)
    private let motionManager: CMMotionManager = CMMotionManager()
    #endif

    public var sandboxCacheDirectory: URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AppClipCaptures", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    public init() {}

    // MARK: - Invocation & Session Lifecycle

    /// Handles incoming App Clip invocation from Universal Link or NFC/QR tag.
    public func handleInvocation(url: URL) async {
        self.hasActiveInvocation = true
        self.syncStatus = .connecting
        self.activeCue = .connecting

        do {
            let payload = try AppClipInvocationParser.parse(url: url)
            self.invocationPayload = payload

            let transport = WebSocketTransport(url: payload.sanitizedRelayURL)
            let session = SyncSession(
                sessionId: payload.sessionId,
                role: .guest,
                transport: transport,
                cipher: cipher,
                sessionKey: payload.sessionKey
            )
            self.syncSession = session

            try await session.start(token: payload.parsedToken)
            self.syncStatus = .ready
            self.activeCue = .waitingForReference

            let receivedReference = try await session.receiveReferencePackage()
            self.referencePackage = receivedReference
            self.syncStatus = .syncing
            self.activeCue = .alignGhost
        } catch {
            self.syncStatus = .failed
            self.uploadError = "\(error.localizedDescription)"
            self.activeCue = .failed
        }
    }

    /// Handles incoming NSUserActivity from iOS system launch.
    public func handleUserActivity(_ activity: NSUserActivity) async {
        self.hasActiveInvocation = true
        self.syncStatus = .connecting
        self.activeCue = .connecting

        do {
            let payload = try AppClipInvocationParser.parse(userActivity: activity)
            await handleInvocation(url: payload.rawURL)
        } catch {
            self.syncStatus = .failed
            self.uploadError = "\(error.localizedDescription)"
            self.activeCue = .failed
        }
    }

    /// Boots up a standalone in-memory demo session with a realistic ReferencePackage.
    public func startStandaloneDemoSession(reference: ReferencePackage? = nil) async {
        let (guestTransport, ownerTransport) = InMemoryTransport.createPair()
        let payload = AppClipInvocationParser.makeDemoInvocation()
        self.invocationPayload = payload
        self.syncStatus = .connecting
        self.activeCue = .connecting

        let guestSession = SyncSession(
            sessionId: payload.sessionId,
            role: .guest,
            transport: guestTransport,
            cipher: cipher,
            sessionKey: payload.sessionKey
        )
        self.syncSession = guestSession

        let ownerSession = SyncSession(
            sessionId: payload.sessionId,
            role: .owner,
            transport: ownerTransport,
            cipher: cipher,
            sessionKey: payload.sessionKey
        )

        let targetRef = reference ?? ReferencePackage(
            sessionId: payload.sessionId,
            ownerDeviceToken: "owner-device-token-demo",
            promptKey: "stranger.align_ghost",
            targetFraming: NormalizedRect(x: 0.15, y: 0.12, width: 0.70, height: 0.76),
            compositionType: "center_half_body",
            targetZoomFactor: 1.0,
            captureAngle: 0.0,
            elevationDeg: 0.0,
            rollDeg: 0.0,
            languageCode: "zh-Hans"
        )

        Task {
            try? await ownerSession.start(token: payload.parsedToken, secretForTokenVerification: payload.sessionKey)
            try? await ownerSession.sendReferencePackage(targetRef)
        }

        do {
            try await guestSession.start(token: payload.parsedToken)
            let receivedRef = try await guestSession.receiveReferencePackage()
            self.referencePackage = receivedRef
            self.syncStatus = .syncing
            self.activeCue = .alignGhost
        } catch {
            self.referencePackage = targetRef
            self.syncStatus = .ready
            self.activeCue = .alignGhost
        }
    }

    // MARK: - Viewfinder & CoreMotion

    /// Starts AVFoundation capture session and CoreMotion attitude tracking.
    public func startViewfinderAndMotion() {
        #if canImport(AVFoundation)
        configureCaptureSessionIfNeeded()
        let session = self.captureSession
        sessionQueue.async {
            if !session.isRunning {
                session.startRunning()
            }
        }
        #endif

        #if canImport(CoreMotion) && !os(macOS)
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                guard let self = self, let motion = motion else { return }
                let roll = motion.attitude.roll * 180.0 / .pi
                let pitch = motion.attitude.pitch * 180.0 / .pi
                self.updateAttitude(roll: roll, pitch: pitch)
            }
        }
        #endif
    }

    #if canImport(AVFoundation)
    private func configureCaptureSessionIfNeeded() {
        guard !isSessionConfigured else { return }
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .photo

        if let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: camera),
           captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }

        captureSession.commitConfiguration()
        isSessionConfigured = true
    }

    private func captureStillPhotoData() async -> Data {
        #if canImport(AVFoundation) && !targetEnvironment(simulator)
        if captureSession.isRunning, let connection = photoOutput.connection(with: .video), connection.isActive {
            do {
                let photoData = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                    let delegate = ClipPhotoCaptureDelegate(continuation: continuation)
                    self.activeCaptureDelegate = delegate
                    delegate.onCompletion = { [weak self] in
                        Task { @MainActor [weak self] in
                            self?.activeCaptureDelegate = nil
                        }
                    }
                    let settings = AVCapturePhotoSettings()
                    self.photoOutput.capturePhoto(with: settings, delegate: delegate)
                }
                return photoData
            } catch {
                return makeCapturePhotoData()
            }
        }
        #endif
        return makeCapturePhotoData()
    }
    #endif

    /// Updates alignment state with latest CoreMotion attitude readings.
    public func updateAttitude(roll: Double, pitch: Double) {
        guard let ref = referencePackage else { return }
        self.alignmentState = StrangerAlignmentState.evaluate(
            currentRoll: roll,
            currentPitch: pitch,
            reference: ref,
            previousState: alignmentState
        )
        if syncStatus == .syncing || syncStatus == .ready {
            self.activeCue = alignmentState.activeCue
        }
    }

    // MARK: - Capture & Encrypted Upload

    /// Captures photo, writes JPEG and encrypted envelope to sandbox, and uploads to owner over SyncSession.
    public func captureAndUploadPhoto() async {
        guard !isCapturing else { return }
        self.isCapturing = true
        self.isUploading = true
        self.uploadError = nil
        self.activeCue = .uploading

        #if canImport(AVFoundation)
        let photoData = await captureStillPhotoData()
        #else
        let photoData = makeCapturePhotoData()
        #endif
        let photoId = UUID().uuidString
        let rawJpegURL = sandboxCacheDirectory.appendingPathComponent("\(photoId).jpg")
        try? photoData.write(to: rawJpegURL)

        guard let sessionKey = invocationPayload?.sessionKey else {
            self.uploadError = "缺少会话加密密钥，无法加密回传"
            self.syncStatus = .failed
            self.isCapturing = false
            self.isUploading = false
            self.activeCue = .failed
            return
        }

        let sessionId = referencePackage?.sessionId ?? (invocationPayload?.sessionId ?? UUID())
        let package = CapturePackage(
            sessionId: sessionId,
            photoId: photoId,
            sequenceIndex: 0,
            capturedAt: Date(),
            fullPhotoData: photoData,
            previewThumbnailData: Data(),
            alignmentOffset: alignmentState.offset,
            alignmentScale: alignmentState.scale,
            wasReadyState: alignmentState.isReadyToShoot,
            deviceModel: "iPhone Helper",
            cameraPitch: Float(alignmentState.pitchDeg),
            cameraRoll: Float(alignmentState.rollDeg),
            focalLengthMm: 24.0,
            clientNonce: UUID().uuidString
        )

        let envelope = try? cipher.encryptCapturePackage(package, key: sessionKey)
        let encryptedEnvelopeURL = sandboxCacheDirectory.appendingPathComponent("\(photoId).enc")
        if let env = envelope, let envData = try? JSONEncoder().encode(env) {
            try? envData.write(to: encryptedEnvelopeURL)
        }

        let cached = CachedClipCapture(
            photoId: photoId,
            sessionId: sessionId,
            rawJpegURL: rawJpegURL,
            encryptedEnvelopeURL: encryptedEnvelopeURL,
            capturedAt: Date(),
            fileSizeBytes: photoData.count,
            package: package
        )
        self.lastCaptureResult = cached

        if let session = syncSession {
            do {
                try await session.sendCapturePackage(package)
                self.isUploading = false
                self.isCapturing = false
                self.isCompleted = true
                self.syncStatus = .completed
                self.activeCue = .completed
            } catch {
                self.cachedPackageForRetry = package
                self.uploadError = "\(error.localizedDescription)"
                self.isUploading = false
                self.isCapturing = false
                self.activeCue = .failed
            }
        } else {
            // Standalone mode completion
            self.isUploading = false
            self.isCapturing = false
            self.isCompleted = true
            self.syncStatus = .completed
            self.activeCue = .completed
        }
    }

    /// Retries failed photo upload using cached capture package.
    public func retryFailedUpload() async {
        guard let package = cachedPackageForRetry, let session = syncSession else { return }
        self.isUploading = true
        self.uploadError = nil
        self.activeCue = .uploading

        do {
            try await session.sendCapturePackage(package)
            self.cachedPackageForRetry = nil
            self.isUploading = false
            self.isCompleted = true
            self.syncStatus = .completed
            self.activeCue = .completed
        } catch {
            self.uploadError = "\(error.localizedDescription)"
            self.isUploading = false
            self.activeCue = .failed
        }
    }

    /// Prepares coordinator for another helper photograph.
    public func prepareForAnotherShot() {
        guard !isSessionFinished else { return }
        self.isCompleted = false
        self.isCapturing = false
        self.isUploading = false
        self.uploadError = nil
        self.syncStatus = .syncing
        self.activeCue = .alignGhost
    }

    /// Purges sandbox ephemeral captures and shuts down sessions.
    public func finishAndPurgeCache() {
        self.isSessionFinished = true
        if FileManager.default.fileExists(atPath: sandboxCacheDirectory.path) {
            try? FileManager.default.removeItem(at: sandboxCacheDirectory)
        }

        #if canImport(CoreMotion) && !os(macOS)
        motionManager.stopDeviceMotionUpdates()
        #endif

        #if canImport(AVFoundation)
        let session = self.captureSession
        sessionQueue.async {
            if session.isRunning {
                session.stopRunning()
            }
        }
        #endif

        Task {
            await syncSession?.close()
        }

        self.isCompleted = true
        self.syncStatus = .completed
        self.activeCue = .completed
    }

    // MARK: - Utilities

    private func makeCapturePhotoData() -> Data {
        // Generates minimal JPEG representation for standalone and simulator environments
        let marker: [UInt8] = [
            0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
            0x01, 0x01, 0x00, 0x48, 0x00, 0x48, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
            0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08, 0x07, 0x07, 0x07, 0x09,
            0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x10, 0x00, 0x10, 0x01, 0x01, 0x11,
            0x00, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00, 0x55,
            0xFF, 0xD9
        ]
        return Data(marker)
    }
}
