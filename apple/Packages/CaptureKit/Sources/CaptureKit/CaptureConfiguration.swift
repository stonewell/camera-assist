import Foundation
import CoreGraphics

#if canImport(AVFoundation)
import AVFoundation
#endif

/// Specification and operational parameters for 24MP high-fidelity camera capture.
public struct CaptureConfiguration: Sendable, Equatable {
    /// Target maximum photo resolution (defaults to 24MP: 5712 x 4284).
    public var maxPhotoWidth: Int
    public var maxPhotoHeight: Int
    
    /// Target preview frame rate (nominal: 60 FPS, thermal fallback: 30 FPS).
    public var targetFrameRate: Int
    
    /// Pixel format for video data output analysis buffer.
    public var pixelFormatType: UInt32
    
    /// Enable Apple system computational photography (Deep Fusion, Photonic Engine, Deferred Processing).
    public var enableDeferredProcessing: Bool
    public var enableZeroShutterLag: Bool
    public var enableResponsiveCapture: Bool
    public var enableDepthData: Bool

    public init(
        maxPhotoWidth: Int = 5712,
        maxPhotoHeight: Int = 4284,
        targetFrameRate: Int = 60,
        pixelFormatType: UInt32 = 0x34323066, // '420f' kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        enableDeferredProcessing: Bool = true,
        enableZeroShutterLag: Bool = true,
        enableResponsiveCapture: Bool = true,
        enableDepthData: Bool = false
    ) {
        self.maxPhotoWidth = maxPhotoWidth
        self.maxPhotoHeight = maxPhotoHeight
        self.targetFrameRate = targetFrameRate
        self.pixelFormatType = pixelFormatType
        self.enableDeferredProcessing = enableDeferredProcessing
        self.enableZeroShutterLag = enableZeroShutterLag
        self.enableResponsiveCapture = enableResponsiveCapture
        self.enableDepthData = enableDepthData
    }

    /// Default 24MP profile conforming to iOS native Camera quality.
    public static let standard24MP = CaptureConfiguration()

    /// Total pixel count of target still capture.
    public var totalPixels: Int {
        maxPhotoWidth * maxPhotoHeight
    }
}

/// Device camera lens types supported for scene capture.
public enum CameraLensType: String, Sendable, CaseIterable {
    case ultraWide = "UltraWide"
    case wide = "Wide"
    case telephoto = "Telephoto"
    case virtualMultiCamera = "VirtualMultiCamera"
}

/// Thermal state reflecting hardware load and throttling policies.
public enum CameraThermalState: String, Sendable {
    case nominal
    case fair
    case serious
    case critical
}
