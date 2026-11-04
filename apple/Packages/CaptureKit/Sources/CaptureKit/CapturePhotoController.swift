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

/// Errors occurring during photo capture requests.
public enum CapturePhotoError: Error, LocalizedError, Sendable, Equatable {
    case captureInProgress
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .captureInProgress:
            return "A photo capture request is already in progress."
        case .cancelled:
            return "Photo capture was cancelled."
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

/// Controller responsible for still photograph capture using Apple's 24MP computational imaging pipeline,
/// Deferred Photo Proxy delivery, PhotoKit library saving, and sandbox fallback persistence.
public final class CapturePhotoController: NSObject, @unchecked Sendable {
    public let configuration: CaptureConfiguration
    public var captureAngle: CGFloat = 90.0

    private let lock = NSLock()
    private var activeContinuation: CheckedContinuation<PhotoCaptureResult, Error>?

    public init(configuration: CaptureConfiguration = .standard24MP) {
        self.configuration = configuration
        super.init()
    }

    /// Atomically retrieves and clears the active continuation.
    fileprivate func popContinuation() -> CheckedContinuation<PhotoCaptureResult, Error>? {
        lock.lock()
        defer { lock.unlock() }
        let cont = activeContinuation
        activeContinuation = nil
        return cont
    }

    /// Cancels any currently active capture continuation.
    public func cancelActiveCapture() {
        popContinuation()?.resume(throwing: CapturePhotoError.cancelled)
    }

    /// Checks if a capture is currently in progress.
    public var isCapturing: Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeContinuation != nil
    }

    /// Trigger 24MP capture (via `AVCapturePhotoOutput` when attached, or mock pipeline in CI/Simulator).
    public func capturePhoto(
        from photoOutput: AnyObject? = nil,
        captureAngle: CGFloat? = nil,
        orientation: CGImagePropertyOrientation? = nil
    ) async throws -> PhotoCaptureResult {
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

            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    self.lock.lock()
                    if self.activeContinuation != nil {
                        self.lock.unlock()
                        continuation.resume(throwing: CapturePhotoError.captureInProgress)
                        return
                    }
                    self.activeContinuation = continuation
                    self.lock.unlock()

                    let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
                    settings.photoQualityPrioritization = .quality
                    settings.maxPhotoDimensions = output.maxPhotoDimensions
                    output.capturePhoto(with: settings, delegate: self)
                }
            } onCancel: { [weak self] in
                self?.cancelActiveCapture()
            }
        }
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
extension CapturePhotoController: AVCapturePhotoCaptureDelegate {
    public func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCapturingDeferredPhotoProxy deferredPhotoProxy: AVCaptureDeferredPhotoProxy?,
        error: Error?
    ) {
        guard let continuation = popContinuation() else { return }
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

    public func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard let continuation = popContinuation() else { return }
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
}
#endif
