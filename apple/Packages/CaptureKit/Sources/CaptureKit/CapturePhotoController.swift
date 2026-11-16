import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
#endif

#if canImport(ImageIO)
import ImageIO
#endif

#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(Photos)
import Photos
#endif

/// Flash mode choices for still photo capture.
public enum CaptureFlashMode: String, Sendable, CaseIterable, Equatable {
    case auto
    case on
    case off
}

/// Errors occurring during photo capture requests.
public enum CapturePhotoError: Error, LocalizedError, Sendable, Equatable {
    case captureInProgress
    case cancelled
    case timeout
    case storageFull

    public var errorDescription: String? {
        switch self {
        case .captureInProgress:
            return "A photo capture request is already in progress."
        case .cancelled:
            return "Photo capture was cancelled."
        case .timeout:
            return "24MP 拍照超时（> 2.5s），已自动重置。"
        case .storageFull:
            return "设备存储空间不足，无法保存照片。"
        }
    }
}

/// Result of a 24MP still photo capture request.
public struct PhotoCaptureResult: Sendable {
    public let timestamp: Double
    public let width: Int
    public let height: Int
    public let isDeferredProxy: Bool
    public let rawData: Data?
    public let savedFileURL: URL?

    public init(
        timestamp: Double = CFAbsoluteTimeGetCurrent(),
        width: Int = 5712,
        height: Int = 4284,
        isDeferredProxy: Bool = true,
        rawData: Data? = nil,
        savedFileURL: URL? = nil
    ) {
        self.timestamp = timestamp
        self.width = width
        self.height = height
        self.isDeferredProxy = isDeferredProxy
        self.rawData = rawData
        self.savedFileURL = savedFileURL
    }
}

/// Internal model storing active in-flight capture state and its timeout watchdog task.
fileprivate struct ActiveCaptureEntry: @unchecked Sendable {
    let id: Int64
    let continuation: CheckedContinuation<PhotoCaptureResult, Error>
    var watchdogTask: Task<Void, Never>?
    var delegateWrapper: AnyObject?
}

/// Controller responsible for still photograph capture using Apple's 24MP computational imaging pipeline,
/// Deferred Photo Proxy delivery, PhotoKit library saving, and sandbox fallback persistence.
public final class CapturePhotoController: NSObject, @unchecked Sendable {
    public let configuration: CaptureConfiguration
    public var captureAngle: CGFloat = 90.0
    public var captureTimeoutNanoseconds: UInt64 = 2_500_000_000
    public var freeDiskSpaceOverride: Int64?
    public var simulateCaptureDelayNanoseconds: UInt64?

    private let lock = NSLock()
    private var activeCaptures: [Int64: ActiveCaptureEntry] = [:]
    private var nextSimulatedID: Int64 = -1

    public init(configuration: CaptureConfiguration = .standard24MP) {
        self.configuration = configuration
        super.init()
    }

    private func generateSimulatedID() -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        let id = nextSimulatedID
        if nextSimulatedID == Int64.min {
            nextSimulatedID = -1
        } else {
            nextSimulatedID -= 1
        }
        return id
    }

    /// Atomically retrieves and clears the active continuation for the specified request ID along with canceling its watchdog task.
    @discardableResult
    fileprivate func popContinuation(forID id: Int64) -> CheckedContinuation<PhotoCaptureResult, Error>? {
        lock.lock()
        guard let entry = activeCaptures.removeValue(forKey: id) else {
            lock.unlock()
            return nil
        }
        lock.unlock()
        entry.watchdogTask?.cancel()
        return entry.continuation
    }

    /// Atomically retrieves and clears any active continuation along with canceling its watchdog task (for backwards compatibility).
    @discardableResult
    fileprivate func popContinuation() -> CheckedContinuation<PhotoCaptureResult, Error>? {
        lock.lock()
        guard let firstKey = activeCaptures.keys.first, let entry = activeCaptures.removeValue(forKey: firstKey) else {
            lock.unlock()
            return nil
        }
        lock.unlock()
        entry.watchdogTask?.cancel()
        return entry.continuation
    }

    /// Starts the watchdog timer that cancels the active capture for the given request ID on timeout.
    private func startWatchdog(forID id: Int64) -> Task<Void, Never> {
        let timeout = captureTimeoutNanoseconds
        return Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: timeout)
            } catch {
                return
            }
            guard let self = self else { return }
            self.cancelActiveCapture(id: id, error: CapturePhotoError.timeout)
        }
    }

    /// Cancels the active capture continuation for the specified request ID with a custom error (defaults to .cancelled).
    public func cancelActiveCapture(id: Int64, error: Error = CapturePhotoError.cancelled) {
        guard let continuation = popContinuation(forID: id) else { return }
        continuation.resume(throwing: error)
    }

    /// Cancels any currently active capture continuations with a custom error (defaults to .cancelled).
    public func cancelActiveCapture(with error: Error = CapturePhotoError.cancelled) {
        lock.lock()
        let entries = Array(activeCaptures.values)
        activeCaptures.removeAll()
        lock.unlock()

        for entry in entries {
            entry.watchdogTask?.cancel()
            entry.continuation.resume(throwing: error)
        }
    }

    /// Cancels any currently active capture continuations.
    public func cancelActiveCapture() {
        cancelActiveCapture(with: CapturePhotoError.cancelled)
    }

    /// Checks if a capture is currently in progress.
    public var isCapturing: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !activeCaptures.isEmpty
    }

    /// Validates available storage on temporary directory, requiring at least 100MB free.
    private func checkAvailableStorage() throws {
        let freeBytes: Int64?
        if let override = freeDiskSpaceOverride {
            freeBytes = override
        } else {
            let tempPath = NSTemporaryDirectory()
            if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: tempPath) {
                if let num = attrs[.systemFreeSize] as? NSNumber {
                    freeBytes = num.int64Value
                } else if let intVal = attrs[.systemFreeSize] as? Int64 {
                    freeBytes = intVal
                } else {
                    freeBytes = nil
                }
            } else {
                freeBytes = nil
            }
        }

        if let free = freeBytes, free < (100 * 1024 * 1024) {
            throw CapturePhotoError.storageFull
        }
    }

    /// Trigger 24MP capture (via `AVCapturePhotoOutput` when attached, or mock pipeline in CI/Simulator).
    public func capturePhoto(
        from photoOutput: AnyObject? = nil,
        captureAngle: CGFloat? = nil,
        orientation: CGImagePropertyOrientation? = nil,
        flashMode: CaptureFlashMode = .auto
    ) async throws -> PhotoCaptureResult {
        try checkAvailableStorage()

        let resolvedAngle: CGFloat
        if let angle = captureAngle {
            resolvedAngle = angle
        } else if let orientation = orientation {
            resolvedAngle = VisionOrientationMapper.captureAngle(for: orientation)
        } else {
            resolvedAngle = self.captureAngle
        }

        #if canImport(AVFoundation) && os(iOS) && !targetEnvironment(simulator)
        if let output = photoOutput as? AVCapturePhotoOutput {
            if let connection = output.connection(with: .video) {
                let normalizedDeg = CGFloat(Int(((resolvedAngle.rounded()).truncatingRemainder(dividingBy: 360.0) + 360.0).truncatingRemainder(dividingBy: 360.0)))
                if connection.isVideoRotationAngleSupported(normalizedDeg) {
                    connection.videoRotationAngle = normalizedDeg
                } else if connection.isVideoRotationAngleSupported(resolvedAngle) {
                    connection.videoRotationAngle = resolvedAngle
                }
            }

            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            settings.photoQualityPrioritization = .quality
            settings.maxPhotoDimensions = output.maxPhotoDimensions

            let avFlashMode: AVCaptureDevice.FlashMode
            switch flashMode {
            case .auto:
                avFlashMode = .auto
            case .on:
                avFlashMode = .on
            case .off:
                avFlashMode = .off
            }
            if output.supportedFlashModes.contains(avFlashMode) {
                settings.flashMode = avFlashMode
            }

            let requestID = settings.uniqueID

            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    self.lock.lock()
                    if !self.activeCaptures.isEmpty {
                        self.lock.unlock()
                        continuation.resume(throwing: CapturePhotoError.captureInProgress)
                        return
                    }
                    let delegateWrapper = PhotoCaptureRequestDelegate(requestID: requestID, controller: self)
                    self.activeCaptures[requestID] = ActiveCaptureEntry(
                        id: requestID,
                        continuation: continuation,
                        watchdogTask: nil,
                        delegateWrapper: delegateWrapper
                    )
                    self.lock.unlock()

                    let watchdog = self.startWatchdog(forID: requestID)
                    self.lock.lock()
                    if self.activeCaptures[requestID] != nil {
                        self.activeCaptures[requestID]?.watchdogTask = watchdog
                    } else {
                        watchdog.cancel()
                    }
                    self.lock.unlock()

                    output.capturePhoto(with: settings, delegate: delegateWrapper)
                }
            } onCancel: { [weak self] in
                self?.cancelActiveCapture(id: requestID)
            }
        }
        #endif

        if let delay = simulateCaptureDelayNanoseconds {
            let requestID = generateSimulatedID()

            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    self.lock.lock()
                    if !self.activeCaptures.isEmpty {
                        self.lock.unlock()
                        continuation.resume(throwing: CapturePhotoError.captureInProgress)
                        return
                    }
                    self.activeCaptures[requestID] = ActiveCaptureEntry(
                        id: requestID,
                        continuation: continuation,
                        watchdogTask: nil,
                        delegateWrapper: nil
                    )
                    self.lock.unlock()

                    let watchdog = self.startWatchdog(forID: requestID)
                    self.lock.lock()
                    if self.activeCaptures[requestID] != nil {
                        self.activeCaptures[requestID]?.watchdogTask = watchdog
                    } else {
                        watchdog.cancel()
                    }
                    self.lock.unlock()

                    Task {
                        do {
                            try await Task.sleep(nanoseconds: delay)
                        } catch {
                            return
                        }
                        guard let cont = self.popContinuation(forID: requestID) else { return }
                        cont.resume(returning: PhotoCaptureResult(
                            timestamp: CFAbsoluteTimeGetCurrent(),
                            width: self.configuration.maxPhotoWidth,
                            height: self.configuration.maxPhotoHeight,
                            isDeferredProxy: true,
                            rawData: Data([0xFF, 0xD8, 0xFF, 0xE0])
                        ))
                    }
                }
            } onCancel: { [weak self] in
                self?.cancelActiveCapture(id: requestID)
            }
        }

        #if canImport(AVFoundation) && os(iOS) && !targetEnvironment(simulator)
        return PhotoCaptureResult(
            timestamp: CFAbsoluteTimeGetCurrent(),
            width: configuration.maxPhotoWidth,
            height: configuration.maxPhotoHeight,
            isDeferredProxy: configuration.enableDeferredProcessing,
            rawData: nil
        )
        #else
        return PhotoCaptureResult(
            timestamp: CFAbsoluteTimeGetCurrent(),
            width: configuration.maxPhotoWidth,
            height: configuration.maxPhotoHeight,
            isDeferredProxy: true,
            rawData: Data([0xFF, 0xD8, 0xFF, 0xE0])
        )
        #endif
    }

    /// Saves captured photo data to the app sandbox (used for App Clip or when Photo Library access is restricted).
    public func saveToSandbox(data: Data, fileExtension: String = "heic") throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("CameraAssistCaptures", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let filename = "IMG_\(Int(Date().timeIntervalSince1970 * 1000)).\(fileExtension)"
        let fileURL = dir.appendingPathComponent(filename)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    deinit {
        cancelActiveCapture()
    }
}

#if canImport(AVFoundation) && os(iOS) && !targetEnvironment(simulator)
fileprivate final class PhotoCaptureRequestDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let requestID: Int64
    private weak var controller: CapturePhotoController?

    init(requestID: Int64, controller: CapturePhotoController) {
        self.requestID = requestID
        self.controller = controller
        super.init()
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCapturingDeferredPhotoProxy deferredPhotoProxy: AVCaptureDeferredPhotoProxy?,
        error: Error?
    ) {
        controller?.handleDeferredPhotoProxy(
            requestID: requestID,
            output: output,
            deferredPhotoProxy: deferredPhotoProxy,
            error: error
        )
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        controller?.handlePhoto(
            requestID: requestID,
            output: output,
            photo: photo,
            error: error
        )
    }
}

extension CapturePhotoController: AVCapturePhotoCaptureDelegate {
    fileprivate func handleDeferredPhotoProxy(
        requestID: Int64,
        output: AVCapturePhotoOutput,
        deferredPhotoProxy: AVCaptureDeferredPhotoProxy?,
        error: Error?
    ) {
        guard let continuation = popContinuation(forID: requestID) else { return }
        if let error = error {
            continuation.resume(throwing: error)
            return
        }
        let data = deferredPhotoProxy?.fileDataRepresentation()
        let savedURL = data.flatMap { try? saveToSandbox(data: $0) }
        #if canImport(Photos)
        if let proxyData = data {
            PHPhotoLibrary.shared().performChanges({
                let req = PHAssetCreationRequest.forAsset()
                req.addResource(with: .photoProxy, data: proxyData, options: nil)
            }, completionHandler: nil)
        }
        #endif
        let dims = output.maxPhotoDimensions
        continuation.resume(
            returning: PhotoCaptureResult(
                timestamp: CFAbsoluteTimeGetCurrent(),
                width: Int(dims.width > 0 ? dims.width : Int32(configuration.maxPhotoWidth)),
                height: Int(dims.height > 0 ? dims.height : Int32(configuration.maxPhotoHeight)),
                isDeferredProxy: true,
                rawData: data,
                savedFileURL: savedURL
            )
        )
    }

    fileprivate func handlePhoto(
        requestID: Int64,
        output: AVCapturePhotoOutput,
        photo: AVCapturePhoto,
        error: Error?
    ) {
        guard let continuation = popContinuation(forID: requestID) else { return }
        if let error = error {
            continuation.resume(throwing: error)
            return
        }
        let data = photo.fileDataRepresentation()
        let savedURL = data.flatMap { try? saveToSandbox(data: $0) }
        #if canImport(Photos)
        if let photoData = data {
            PHPhotoLibrary.shared().performChanges({
                let req = PHAssetCreationRequest.forAsset()
                req.addResource(with: .photo, data: photoData, options: nil)
            }, completionHandler: nil)
        }
        #endif
        let dims = photo.resolvedSettings.photoDimensions
        continuation.resume(
            returning: PhotoCaptureResult(
                timestamp: CFAbsoluteTimeGetCurrent(),
                width: Int(dims.width > 0 ? dims.width : Int32(configuration.maxPhotoWidth)),
                height: Int(dims.height > 0 ? dims.height : Int32(configuration.maxPhotoHeight)),
                isDeferredProxy: false,
                rawData: data,
                savedFileURL: savedURL
            )
        )
    }

    public func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCapturingDeferredPhotoProxy deferredPhotoProxy: AVCaptureDeferredPhotoProxy?,
        error: Error?
    ) {
        lock.lock()
        let matchingID = activeCaptures.keys.first
        lock.unlock()
        guard let id = matchingID else { return }
        handleDeferredPhotoProxy(requestID: id, output: output, deferredPhotoProxy: deferredPhotoProxy, error: error)
    }

    public func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let id = photo.resolvedSettings.uniqueID
        handlePhoto(requestID: id, output: output, photo: photo, error: error)
    }
}
#endif
