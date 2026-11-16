import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
#endif

#if canImport(CoreVideo)
import CoreVideo
#endif

#if canImport(ImageIO)
import ImageIO
#endif

#if canImport(CoreMedia)
import CoreMedia
#endif

#if canImport(AVFoundation)
import AVFoundation
#endif

/// Errors and interruptions occurring during camera capture session execution.
public enum CaptureSessionRuntimeError: Error, LocalizedError, Sendable, Equatable {
    case hardwareInUseByAnotherClient(String)
    case audioInterruption(String)
    case backgroundSessionInterrupted(String)
    case multiAppInterrupted(String)
    case sessionRuntimeFailure(String)

    public var errorDescription: String? {
        switch self {
        case .hardwareInUseByAnotherClient(let msg):
            return "相机硬件已被其他应用占用: \(msg)"
        case .audioInterruption(let msg):
            return "音频输入中断: \(msg)"
        case .backgroundSessionInterrupted(let msg):
            return "后台运行导致相机断开: \(msg)"
        case .multiAppInterrupted(let msg):
            return "多任务前台模式导致相机不可用: \(msg)"
        case .sessionRuntimeFailure(let msg):
            return "相机运行时异常: \(msg)"
        }
    }
}

/// Comprehensive optical, exposure, and hardware metadata extracted per video sample frame.
public struct CameraFrameMetadata: Sendable, Equatable {
    public let orientation: CGImagePropertyOrientation
    public let iso: Float
    public let shutterSpeedSeconds: Double
    public let exposureBias: Float
    public let lensAperture: Float
    public let focalLengthMm: Float
    public let hfovDeg: Float
    public let intrinsicMatrix: [Float]?
    public let thermalState: CameraThermalState
    public let rawExif: [String: String]

    public init(
        orientation: CGImagePropertyOrientation = .right,
        iso: Float = 100.0,
        shutterSpeedSeconds: Double = 1.0 / 500.0,
        exposureBias: Float = 0.0,
        lensAperture: Float = 1.8,
        focalLengthMm: Float = 24.0,
        hfovDeg: Float = 73.7,
        intrinsicMatrix: [Float]? = nil,
        thermalState: CameraThermalState = .nominal,
        rawExif: [String: String] = [:]
    ) {
        self.orientation = orientation
        self.iso = iso
        self.shutterSpeedSeconds = shutterSpeedSeconds
        self.exposureBias = exposureBias
        self.lensAperture = lensAperture
        self.focalLengthMm = focalLengthMm
        self.hfovDeg = hfovDeg
        self.intrinsicMatrix = intrinsicMatrix
        self.thermalState = thermalState
        self.rawExif = rawExif
    }

    /// Computed Exposure Value (EV100) combining aperture, shutter speed, ISO and bias.
    public var ev: Float {
        let n = Double(lensAperture > 0 ? lensAperture : 1.8)
        let t = Double(shutterSpeedSeconds > 0 ? shutterSpeedSeconds : 1.0 / 60.0)
        let isoVal = Double(iso > 0 ? iso : 100.0)
        let ev100 = log2((n * n) / t) - log2(isoVal / 100.0)
        return Float(ev100) + exposureBias
    }
}

/// Lightweight abstraction of a video frame passing through the analysis pipeline.
/// Carries CVPixelBuffer, camera orientation, and rich optical/EXIF metadata without dropping them.
public struct VideoSampleFrame: @unchecked Sendable {
    public let presentationTimestamp: Double
    public let width: Int
    public let height: Int
    public let pixelFormat: UInt32
    public let isMock: Bool
    public let pixelBuffer: CVPixelBuffer?
    public let orientation: CGImagePropertyOrientation
    public let metadata: CameraFrameMetadata?

    public init(
        presentationTimestamp: Double,
        width: Int = 1920,
        height: Int = 1080,
        pixelFormat: UInt32 = 0x34323066,
        isMock: Bool = false,
        pixelBuffer: CVPixelBuffer? = nil,
        orientation: CGImagePropertyOrientation = .right,
        metadata: CameraFrameMetadata? = nil
    ) {
        self.presentationTimestamp = presentationTimestamp
        self.width = width
        self.height = height
        self.pixelFormat = pixelFormat
        self.isMock = isMock
        self.pixelBuffer = pixelBuffer
        self.orientation = orientation
        self.metadata = metadata
    }

    // Convenience accessors delegating to metadata
    public var iso: Float? { metadata?.iso }
    public var shutterSpeedSeconds: Double? { metadata?.shutterSpeedSeconds }
    public var exposureBias: Float? { metadata?.exposureBias }
    public var lensAperture: Float? { metadata?.lensAperture }
    public var focalLengthMm: Float? { metadata?.focalLengthMm }
    public var hfovDeg: Float? { metadata?.hfovDeg }
    public var intrinsicMatrix: [Float]? { metadata?.intrinsicMatrix }
    public var thermalState: CameraThermalState? { metadata?.thermalState }
    public var ev: Float? { metadata?.ev }
    public var rawExif: [String: String] { metadata?.rawExif ?? [:] }
}

/// Protocol abstracting camera capture session capabilities.
public protocol CaptureSessionManaging: AnyObject, Sendable {
    var isRunning: Bool { get }
    var configuration: CaptureConfiguration { get }
    var currentLens: CameraLensType { get }
    var currentThermalState: CameraThermalState { get }
    var effectiveFrameRate: Int { get }
    var onRuntimeError: (@Sendable (CaptureSessionRuntimeError) -> Void)? { get set }
    func startSession() async throws
    func stopSession() async
    func switchLens(to lens: CameraLensType) async throws
    func setThermalState(_ state: CameraThermalState) async
}

/// Production AVCaptureSession manager for Camera Assist.
/// Manages high-performance 24MP capture session, prepared photo settings, Camera Control sliders,
/// tap-to-focus/exposure, 60fps video data output, real KVO device rotation synchronization,
/// and automatic 60fps -> 30fps thermal throttling.
public final class CaptureSessionManager: NSObject, @unchecked Sendable, CaptureSessionManaging {
    public private(set) var isRunning: Bool = false
    public let configuration: CaptureConfiguration
    public let rotationBridge: RotationCoordinatorBridge
    public var rotationCoordinatorBridge: RotationCoordinatorBridge { rotationBridge }

    public private(set) var currentLens: CameraLensType = .virtualMultiCamera
    public private(set) var currentThermalState: CameraThermalState = .nominal
    public private(set) var effectiveFrameRate: Int
    public private(set) var lastFocusPoint: CGPoint = CGPoint(x: 0.5, y: 0.5)
    public private(set) var currentExposureBias: Float = 0.0

    public typealias FrameHandler = @Sendable (VideoSampleFrame) -> Void
    private var onFrameReceived: FrameHandler?
    public var onRuntimeError: (@Sendable (CaptureSessionRuntimeError) -> Void)?
    private var thermalObserver: NSObjectProtocol?

    #if canImport(AVFoundation)
    public private(set) var session: AVCaptureSession?
    public private(set) var activeDevice: AVCaptureDevice?
    private var videoOutput: AVCaptureVideoDataOutput?
    public private(set) var photoOutput: AVCapturePhotoOutput?
    private var sessionInterruptionObserver: (any NSObjectProtocol)?
    private var sessionInterruptionEndedObserver: (any NSObjectProtocol)?
    private var sessionRuntimeErrorObserver: (any NSObjectProtocol)?
    private let sessionQueue = DispatchQueue(label: "com.cameraassist.capturesession", qos: .userInitiated)
    private let analysisQueue = DispatchQueue(label: "com.cameraassist.analysis", qos: .userInteractive)
    #endif

    public init(
        configuration: CaptureConfiguration = .standard24MP,
        rotationBridge: RotationCoordinatorBridge = RotationCoordinatorBridge(),
        onFrame: FrameHandler? = nil
    ) {
        self.configuration = configuration
        self.rotationBridge = rotationBridge
        self.onFrameReceived = onFrame
        self.effectiveFrameRate = configuration.targetFrameRate
        super.init()
    }

    /// Set handler for incoming video stream frames.
    public func setFrameHandler(_ handler: @escaping FrameHandler) {
        self.onFrameReceived = handler
    }

    /// Start capture session pipeline with 24MP maxPhotoDimensions, prepared settings, Camera Control sliders,
    /// real KVO rotation tracking, and thermal state monitoring.
    public func startSession() async throws {
        startThermalMonitoring()

        #if canImport(AVFoundation) && os(iOS) && !targetEnvironment(simulator)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                if let existing = self.session, existing.isRunning {
                    existing.stopRunning()
                }
                self.stopObservingSessionNotifications()
                let sess = AVCaptureSession()
                sess.beginConfiguration()
                sess.sessionPreset = .photo

                // 1. Configure best available back camera
                let device = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
                    ?? AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
                    ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)

                if let dev = device, let input = try? AVCaptureDeviceInput(device: dev) {
                    if sess.canAddInput(input) {
                        sess.addInput(input)
                        self.activeDevice = dev
                    }
                }

                // Wire real KVO observation of device rotation via RotationCoordinatorBridge
                if #available(iOS 17.0, macOS 14.0, *), let dev = self.activeDevice {
                    self.rotationBridge.observe(device: dev)
                }

                // 2. 24MP Photo Output + maxPhotoDimensions + preparedPhotoSettings
                let photo = AVCapturePhotoOutput()
                photo.maxPhotoQualityPrioritization = .quality
                if sess.canAddOutput(photo) {
                    sess.addOutput(photo)
                    if let dev = self.activeDevice {
                        let supportedDims = dev.activeFormat.supportedMaxPhotoDimensions
                        if let bestDim = supportedDims.max(by: { ($0.width * $0.height) < ($1.width * $1.height) }) {
                            photo.maxPhotoDimensions = bestDim
                        }
                    }
                    if self.configuration.enableDeferredProcessing && photo.isAutoDeferredPhotoDeliverySupported {
                        photo.isAutoDeferredPhotoDeliveryEnabled = true
                    }
                    if self.configuration.enableZeroShutterLag && photo.isZeroShutterLagSupported {
                        photo.isZeroShutterLagEnabled = true
                    }
                    if self.configuration.enableResponsiveCapture && photo.isResponsiveCaptureSupported {
                        photo.isResponsiveCaptureEnabled = true
                    }
                    let prepared = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
                    prepared.photoQualityPrioritization = .quality
                    prepared.maxPhotoDimensions = photo.maxPhotoDimensions
                    photo.setPreparedPhotoSettingsArray([prepared], completionHandler: nil)
                }
                self.photoOutput = photo

                // 3. Configure iOS 18 Camera Control sliders (Zoom & Exposure Bias)
                if #available(iOS 18.0, macOS 15.0, *), let dev = self.activeDevice, sess.supportsControls {
                    for control in sess.controls {
                        sess.removeControl(control)
                    }
                    let zoomSlider = AVCaptureSystemZoomSlider(device: dev)
                    if sess.canAddControl(zoomSlider) {
                        sess.addControl(zoomSlider)
                    }
                    let exposureSlider = AVCaptureSystemExposureBiasSlider(device: dev)
                    if sess.canAddControl(exposureSlider) {
                        sess.addControl(exposureSlider)
                    }
                }

                // 4. Real-time Video Analysis Output (420f/420v)
                let video = AVCaptureVideoDataOutput()
                video.alwaysDiscardsLateVideoFrames = true
                video.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: self.configuration.pixelFormatType
                ]
                video.setSampleBufferDelegate(self, queue: self.analysisQueue)
                if sess.canAddOutput(video) {
                    sess.addOutput(video)
                    if let connection = video.connection(with: .video), connection.isCameraIntrinsicMatrixDeliverySupported {
                        connection.isCameraIntrinsicMatrixDeliveryEnabled = true
                    }
                }
                self.videoOutput = video

                // Apply initial frame rate to device
                self.applyFrameRateToDevice(fps: self.effectiveFrameRate)

                sess.commitConfiguration()
                sess.startRunning()
                self.session = sess
                self.isRunning = sess.isRunning
                self.startObservingSessionNotifications(for: sess)
                continuation.resume()
            }
        }
        #else
        // Mock fallback for simulator, macOS, or CI test harness
        self.isRunning = true
        #endif
    }

    /// Stop capture session, cancel KVO rotation observers, and unregister thermal listeners.
    public func stopSession() async {
        stopThermalMonitoring()
        #if canImport(AVFoundation)
        stopObservingSessionNotifications()
        rotationBridge.stopObserving()
        #endif

        #if canImport(AVFoundation) && os(iOS) && !targetEnvironment(simulator)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                if let sess = self.session, sess.isRunning {
                    sess.stopRunning()
                }
                self.isRunning = false
                continuation.resume()
            }
        }
        #else
        self.isRunning = false
        #endif
    }

    /// Switch active lens type or virtual optical zoom factor (`0.5x`, `1.0x`, `2.0x`, `3.0x`).
    public func switchLens(to lens: CameraLensType) async throws {
        self.currentLens = lens
        #if canImport(AVFoundation) && os(iOS) && !targetEnvironment(simulator)
        sessionQueue.async { [weak self] in
            guard let self = self, let dev = self.activeDevice else { return }
            let targetZoom: CGFloat
            switch lens {
            case .ultraWide: targetZoom = 1.0
            case .wide, .virtualMultiCamera: targetZoom = 2.0
            case .telephoto2x: targetZoom = 4.0
            case .telephoto: targetZoom = 6.0
            }
            if (try? dev.lockForConfiguration()) != nil {
                let clamped = max(dev.minAvailableVideoZoomFactor, min(targetZoom, dev.maxAvailableVideoZoomFactor))
                dev.ramp(toVideoZoomFactor: clamped, withRate: 8.0)
                dev.unlockForConfiguration()
            }
            if #available(iOS 17.0, macOS 14.0, *) {
                self.rotationBridge.observe(device: dev)
            }
        }
        #endif
    }

    /// Tap-to-focus and exposure point of interest in normalized device coordinates `[0, 1]`.
    public func focusAndExpose(at devicePoint: CGPoint) {
        self.lastFocusPoint = devicePoint
        #if canImport(AVFoundation) && os(iOS) && !targetEnvironment(simulator)
        sessionQueue.async { [weak self] in
            guard let dev = self?.activeDevice else { return }
            if (try? dev.lockForConfiguration()) != nil {
                if dev.isFocusPointOfInterestSupported && dev.isFocusModeSupported(.continuousAutoFocus) {
                    dev.focusPointOfInterest = devicePoint
                    dev.focusMode = .continuousAutoFocus
                }
                if dev.isExposurePointOfInterestSupported && dev.isExposureModeSupported(.continuousAutoExposure) {
                    dev.exposurePointOfInterest = devicePoint
                    dev.exposureMode = .continuousAutoExposure
                }
                dev.isSubjectAreaChangeMonitoringEnabled = true
                dev.unlockForConfiguration()
            }
        }
        #endif
    }

    /// Adjusts camera exposure compensation bias (EV).
    public func setExposureBias(_ ev: Float) {
        self.currentExposureBias = ev
        #if canImport(AVFoundation) && os(iOS) && !targetEnvironment(simulator)
        sessionQueue.async { [weak self] in
            guard let dev = self?.activeDevice else { return }
            if (try? dev.lockForConfiguration()) != nil {
                let clamped = max(dev.minExposureTargetBias, min(ev, dev.maxExposureTargetBias))
                dev.setExposureTargetBias(clamped, completionHandler: nil)
                dev.unlockForConfiguration()
            }
        }
        #endif
    }

    // MARK: - Thermal State Throttling (Automatic 60 FPS -> 30 FPS and Restore)

    /// Registers automatic observer for system ProcessInfo thermal state notifications.
    private func startThermalMonitoring() {
        stopThermalMonitoring()
        #if !os(Linux) && canImport(Foundation)
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self = self else { return }
            let processState = ProcessInfo.processInfo.thermalState
            let mapped = self.mapProcessThermalState(processState)
            Task {
                await self.setThermalState(mapped)
            }
        }
        let currentProcessState = ProcessInfo.processInfo.thermalState
        applyThermalState(mapProcessThermalState(currentProcessState))
        #endif
    }

    /// Unregisters system thermal state observer.
    private func stopThermalMonitoring() {
        if let obs = thermalObserver {
            NotificationCenter.default.removeObserver(obs)
            thermalObserver = nil
        }
    }

    #if !os(Linux) && canImport(Foundation)
    /// Maps Foundation `ProcessInfo.ThermalState` to `CameraThermalState`.
    private func mapProcessThermalState(_ state: ProcessInfo.ThermalState) -> CameraThermalState {
        switch state {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .nominal
        }
    }
    #endif

    /// Dynamically throttle capture frame rate based on device thermal pressure.
    /// On `.serious` or `.critical`, automatically drops frame rate to 30 FPS.
    /// On `.fair` or `.nominal`, automatically restores frame rate to configured nominal rate (60 FPS).
    public func setThermalState(_ state: CameraThermalState) async {
        applyThermalState(state)
    }

    /// Internal synchronous application of thermal throttling policy.
    private func applyThermalState(_ state: CameraThermalState) {
        self.currentThermalState = state
        let targetRate: Int
        switch state {
        case .serious, .critical:
            targetRate = min(30, configuration.targetFrameRate)
        case .nominal, .fair:
            targetRate = configuration.targetFrameRate
        }

        self.effectiveFrameRate = targetRate
        applyFrameRateToDevice(fps: targetRate)
    }

    /// Configures active hardware device min/max frame durations to match target FPS.
    private func applyFrameRateToDevice(fps: Int) {
        #if canImport(AVFoundation) && os(iOS) && !targetEnvironment(simulator)
        sessionQueue.async { [weak self] in
            guard let dev = self?.activeDevice else { return }
            do {
                try dev.lockForConfiguration()
                let target = Double(fps)
                if dev.activeFormat.videoSupportedFrameRateRanges.contains(where: {
                    target >= $0.minFrameRate && target <= $0.maxFrameRate
                }) {
                    let frameDuration = CMTime(value: 1, timescale: CMTimeScale(target))
                    dev.activeVideoMinFrameDuration = frameDuration
                    dev.activeVideoMaxFrameDuration = frameDuration
                }
                dev.unlockForConfiguration()
            } catch {
                // Device locked
            }
        }
        #endif
    }

    /// Emits a mock frame for automated test pipelines and verification benchmarks.
    public func emitMockFrame(
        timestamp: Double = CFAbsoluteTimeGetCurrent(),
        pixelBuffer: CVPixelBuffer? = nil,
        orientation: CGImagePropertyOrientation? = nil,
        metadata: CameraFrameMetadata? = nil
    ) {
        let meta = metadata ?? CameraFrameMetadata(
            orientation: orientation ?? rotationBridge.visionOrientation,
            iso: 100.0,
            shutterSpeedSeconds: 1.0 / 500.0,
            exposureBias: currentExposureBias,
            lensAperture: 1.8,
            focalLengthMm: 24.0,
            hfovDeg: 73.7,
            intrinsicMatrix: [
                1000.0, 0.0, 960.0,
                0.0, 1000.0, 540.0,
                0.0, 0.0, 1.0
            ],
            thermalState: currentThermalState,
            rawExif: [
                "ISOSpeedRatings": "100",
                "ExposureTime": "0.002",
                "FNumber": "1.8"
            ]
        )
        let frame = VideoSampleFrame(
            presentationTimestamp: timestamp,
            width: 1920,
            height: 1080,
            pixelFormat: configuration.pixelFormatType,
            isMock: true,
            pixelBuffer: pixelBuffer,
            orientation: meta.orientation,
            metadata: meta
        )
        onFrameReceived?(frame)
    }

    /// Manually dispatches a runtime error, useful for testing and simulated interruption pipelines.
    public func emitRuntimeError(_ error: CaptureSessionRuntimeError) {
        onRuntimeError?(error)
    }

    #if canImport(AVFoundation)
    /// Registers notification observers for session interruption, resumption, and runtime errors.
    private func startObservingSessionNotifications(for session: AVCaptureSession) {
        stopObservingSessionNotifications()

        sessionInterruptionObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            #if os(iOS) || targetEnvironment(macCatalyst)
            var reasonInt: Int? = nil
            if let num = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber {
                reasonInt = num.intValue
            } else if let val = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int {
                reasonInt = val
            }
            if let reasonInt = reasonInt, let reason = AVCaptureSession.InterruptionReason(rawValue: reasonInt) {
                switch reason {
                case .videoDeviceInUseByAnotherClient:
                    self.onRuntimeError?(.hardwareInUseByAnotherClient("videoDeviceInUseByAnotherClient"))
                case .audioDeviceInUseByAnotherClient:
                    self.onRuntimeError?(.audioInterruption("audioDeviceInUseByAnotherClient"))
                case .videoDeviceNotAvailableInBackground:
                    self.onRuntimeError?(.backgroundSessionInterrupted("videoDeviceNotAvailableInBackground"))
                case .videoDeviceNotAvailableWithMultipleForegroundApps:
                    self.onRuntimeError?(.multiAppInterrupted("videoDeviceNotAvailableWithMultipleForegroundApps"))
                default:
                    self.onRuntimeError?(.sessionRuntimeFailure("Interruption reason: \(reasonInt)"))
                }
                return
            }
            #endif
            self.onRuntimeError?(.sessionRuntimeFailure("AVCaptureSession was interrupted"))
        }

        sessionInterruptionEndedObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.isRunning = self.session?.isRunning ?? false
        }

        sessionRuntimeErrorObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            let errorMsg: String
            if let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error {
                errorMsg = error.localizedDescription
            } else {
                errorMsg = "Unknown capture session runtime failure"
            }
            self.isRunning = self.session?.isRunning ?? false
            self.onRuntimeError?(.sessionRuntimeFailure(errorMsg))
        }
    }

    /// Cleans up notification observers for session interruptions and errors.
    private func stopObservingSessionNotifications() {
        if let obs = sessionInterruptionObserver {
            NotificationCenter.default.removeObserver(obs)
            sessionInterruptionObserver = nil
        }
        if let obs = sessionInterruptionEndedObserver {
            NotificationCenter.default.removeObserver(obs)
            sessionInterruptionEndedObserver = nil
        }
        if let obs = sessionRuntimeErrorObserver {
            NotificationCenter.default.removeObserver(obs)
            sessionRuntimeErrorObserver = nil
        }
    }
    #endif

    deinit {
        stopThermalMonitoring()
        #if canImport(AVFoundation)
        stopObservingSessionNotifications()
        rotationBridge.stopObserving()
        #endif
    }
}

#if canImport(AVFoundation)
extension CaptureSessionManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let seconds = CMTimeGetSeconds(timestamp)
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)

        let metadata = extractMetadata(from: sampleBuffer)
        let orientation = rotationBridge.visionOrientation

        let sampleFrame = VideoSampleFrame(
            presentationTimestamp: seconds,
            width: w,
            height: h,
            pixelFormat: format,
            isMock: false,
            pixelBuffer: pixelBuffer,
            orientation: orientation,
            metadata: metadata
        )
        onFrameReceived?(sampleFrame)
    }

    private func extractMetadata(from sampleBuffer: CMSampleBuffer) -> CameraFrameMetadata {
        var iso: Float = activeDevice?.iso ?? 100.0
        var shutterSec: Double = activeDevice.map { CMTimeGetSeconds($0.exposureDuration) } ?? (1.0 / 60.0)
        #if os(iOS) || targetEnvironment(macCatalyst)
        var aperture: Float = activeDevice?.lensAperture ?? 1.8
        let hfov: Float = activeDevice?.activeFormat.videoFieldOfView ?? 73.7
        #else
        var aperture: Float = 1.8
        let hfov: Float = 73.7
        #endif
        var bias: Float = currentExposureBias
        var focalMm: Float = 24.0
        var rawExif: [String: String] = [:]
        var intrinsics: [Float]? = nil

        #if canImport(CoreMedia)
        // 1. Extract Camera Intrinsics Matrix if present
        if let matrixAttachment = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, attachmentModeOut: nil) {
            let cfData = matrixAttachment as! CFData
            let len = CFDataGetLength(cfData)
            if len >= 36, let ptr = CFDataGetBytePtr(cfData) {
                let floats = ptr.withMemoryRebound(to: Float.self, capacity: len / MemoryLayout<Float>.size) { buffer in
                    Array(UnsafeBufferPointer(start: buffer, count: min(9, len / MemoryLayout<Float>.size)))
                }
                intrinsics = floats
            }
        }

        // 2. Extract Propagated Attachments (EXIF dictionary)
        if let dict = CMCopyDictionaryOfAttachments(
            allocator: kCFAllocatorDefault,
            target: sampleBuffer,
            attachmentMode: kCMAttachmentMode_ShouldPropagate
        ) as? [String: Any] {
            if let exif = dict["{Exif}"] as? [String: Any] {
                for (k, v) in exif {
                    rawExif[k] = "\(v)"
                }
                if let isoArray = exif["ISOSpeedRatings"] as? [NSNumber], let first = isoArray.first {
                    iso = first.floatValue
                } else if let isoNum = exif["ISOSpeedRatings"] as? NSNumber {
                    iso = isoNum.floatValue
                }
                if let expTime = exif["ExposureTime"] as? NSNumber {
                    shutterSec = expTime.doubleValue
                }
                if let fNum = exif["FNumber"] as? NSNumber {
                    aperture = fNum.floatValue
                }
                if let fLen = exif["FocalLength"] as? NSNumber {
                    focalMm = fLen.floatValue
                }
                if let expBias = exif["ExposureBiasValue"] as? NSNumber {
                    bias = expBias.floatValue
                }
            }
        }
        #endif

        return CameraFrameMetadata(
            orientation: rotationBridge.visionOrientation,
            iso: iso,
            shutterSpeedSeconds: shutterSec,
            exposureBias: bias,
            lensAperture: aperture,
            focalLengthMm: focalMm,
            hfovDeg: hfov,
            intrinsicMatrix: intrinsics,
            thermalState: currentThermalState,
            rawExif: rawExif
        )
    }

    public func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Drop notification for telemetry
    }
}
#endif
