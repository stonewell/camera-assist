// apple/Spikes/CaptureSpike/CaptureConfig.swift
// Spike #1 Camera Capture Pipeline Configuration Specification

import AVFoundation
import Foundation

/// High-fidelity AVCapturePhotoOutput configuration comparing custom pipeline to iOS native camera.
public struct CaptureSpikeConfig: Sendable {
    /// Desired photo resolution (24MP on iPhone 15/16 Pro).
    public var maxPhotoDimensions: CMVideoDimensions
    
    /// Flash mode (off by default for blind testing consistency).
    public var flashMode: AVCaptureDevice.FlashMode
    
    /// High-resolution capture enabled.
    public var isHighResolutionCaptureEnabled: Bool
    
    /// Target shutter lag ceiling (in milliseconds).
    public var shutterLagCeilingMs: Double

    public init(
        maxPhotoDimensions: CMVideoDimensions = CMVideoDimensions(width: 5712, height: 4284), // 24.47 MP
        flashMode: AVCaptureDevice.FlashMode = .off,
        isHighResolutionCaptureEnabled: Bool = true,
        shutterLagCeilingMs: Double = 100.0
    ) {
        self.maxPhotoDimensions = maxPhotoDimensions
        self.flashMode = flashMode
        self.isHighResolutionCaptureEnabled = isHighResolutionCaptureEnabled
        self.shutterLagCeilingMs = shutterLagCeilingMs
    }

    /// Build AVCapturePhotoSettings configured for 24MP high-quality capture.
    public func createPhotoSettings() -> AVCapturePhotoSettings {
        let settings = AVCapturePhotoSettings(format: [
            AVVideoCodecKey: AVVideoCodecType.hevc
        ])
        settings.flashMode = self.flashMode
        settings.maxPhotoDimensions = self.maxPhotoDimensions
        settings.photoQualityPrioritization = .quality
        return settings
    }
}
