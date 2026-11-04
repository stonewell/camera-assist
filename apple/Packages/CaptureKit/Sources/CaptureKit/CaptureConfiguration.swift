import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
#endif

#if !os(Linux) && canImport(CoreFoundation)
import CoreFoundation
#else
public func CFAbsoluteTimeGetCurrent() -> Double {
    Date().timeIntervalSinceReferenceDate
}
#endif

#if canImport(ImageIO)
import ImageIO
#else
public enum CGImagePropertyOrientation: UInt32, Sendable {
    case up = 1
    case upMirrored = 2
    case down = 3
    case downMirrored = 4
    case leftMirrored = 5
    case right = 6
    case rightMirrored = 7
    case left = 8
}
#endif

#if canImport(CoreVideo)
import CoreVideo
#else
public typealias CVPixelBuffer = AnyObject
#endif

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
public enum CameraThermalState: String, Sendable, CaseIterable {
    case nominal
    case fair
    case serious
    case critical

    /// Whether this thermal state requires frame rate throttling.
    public var isThrottled: Bool {
        self == .serious || self == .critical
    }

    /// Target frame rate under this thermal state (60 FPS nominal, 30 FPS throttled).
    public var targetFrameRate: Int {
        isThrottled ? 30 : 60
    }
}
