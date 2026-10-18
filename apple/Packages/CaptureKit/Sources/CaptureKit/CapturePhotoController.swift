import Foundation
import CoreGraphics

#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(Photos)
import Photos
#endif

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
    private var activeContinuation: CheckedContinuation<PhotoCaptureResult, Error>?

    public init(configuration: CaptureConfiguration = .standard24MP) {
        self.configuration = configuration
        super.init()
    }

    /// Trigger 24MP capture (via `AVCapturePhotoOutput` when attached, or mock pipeline in CI/Simulator).
    public func capturePhoto(from photoOutput: AnyObject? = nil) async throws -> PhotoCaptureResult {
        #if canImport(AVFoundation) && os(iOS) && !targetEnvironment(simulator)
        if let output = photoOutput as? AVCapturePhotoOutput {
            return try await withCheckedThrowingContinuation { continuation in
                self.activeContinuation = continuation
                let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
                settings.photoQualityPrioritization = .quality
                settings.maxPhotoDimensions = output.maxPhotoDimensions
                output.capturePhoto(with: settings, delegate: self)
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
}

#if canImport(AVFoundation) && os(iOS) && !targetEnvironment(simulator)
extension CapturePhotoController: AVCapturePhotoCaptureDelegate {
    public func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCapturingDeferredPhotoProxy deferredPhotoProxy: AVCaptureDeferredPhotoProxy?,
        error: Error?
    ) {
        if let error = error {
            activeContinuation?.resume(throwing: error)
            activeContinuation = nil
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
        activeContinuation?.resume(
            returning: PhotoCaptureResult(
                timestamp: CFAbsoluteTimeGetCurrent(),
                width: Int(dims.width > 0 ? dims.width : Int32(configuration.maxPhotoWidth)),
                height: Int(dims.height > 0 ? dims.height : Int32(configuration.maxPhotoHeight)),
                isDeferredProxy: true,
                rawData: data,
                savedFileURL: savedURL
            )
        )
        activeContinuation = nil
    }

    public func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard activeContinuation != nil else { return }
        if let error = error {
            activeContinuation?.resume(throwing: error)
            activeContinuation = nil
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
        activeContinuation?.resume(
            returning: PhotoCaptureResult(
                timestamp: CFAbsoluteTimeGetCurrent(),
                width: Int(dims.width > 0 ? dims.width : Int32(configuration.maxPhotoWidth)),
                height: Int(dims.height > 0 ? dims.height : Int32(configuration.maxPhotoHeight)),
                isDeferredProxy: false,
                rawData: data,
                savedFileURL: savedURL
            )
        )
        activeContinuation = nil
    }
}
#endif
