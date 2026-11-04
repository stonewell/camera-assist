import XCTest
@testable import CaptureKit

#if canImport(CoreGraphics)
import CoreGraphics
#endif

#if canImport(ImageIO)
import ImageIO
#endif

final class CaptureKitTests: XCTestCase {
    func testConfigurationDefaults() {
        let config = CaptureConfiguration.standard24MP
        XCTAssertEqual(config.maxPhotoWidth, 5712)
        XCTAssertEqual(config.maxPhotoHeight, 4284)
        XCTAssertEqual(config.totalPixels, 24_470_208)
        XCTAssertEqual(config.targetFrameRate, 60)
        XCTAssertTrue(config.enableDeferredProcessing)
        XCTAssertTrue(config.enableZeroShutterLag)
        XCTAssertTrue(config.enableResponsiveCapture)
    }

    private final class FrameBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _frames: [VideoSampleFrame] = []
        var frames: [VideoSampleFrame] {
            lock.lock()
            defer { lock.unlock() }
            return _frames
        }
        func append(_ frame: VideoSampleFrame) {
            lock.lock()
            defer { lock.unlock() }
            _frames.append(frame)
        }
    }

    func testCaptureSessionLifecycleAndMockFrame() async throws {
        let manager = CaptureSessionManager()
        let box = FrameBox()

        manager.setFrameHandler { frame in
            box.append(frame)
        }

        try await manager.startSession()
        XCTAssertTrue(manager.isRunning)

        manager.emitMockFrame(timestamp: 100.0)
        manager.emitMockFrame(timestamp: 100.016)

        let receivedFrames = box.frames
        XCTAssertEqual(receivedFrames.count, 2)
        XCTAssertEqual(receivedFrames[0].presentationTimestamp, 100.0)
        XCTAssertTrue(receivedFrames[0].isMock)
        XCTAssertEqual(receivedFrames[0].orientation, .right)
        XCTAssertEqual(receivedFrames[0].iso, 100.0)
        XCTAssertEqual(receivedFrames[0].focalLengthMm, 24.0)

        await manager.setThermalState(.serious)
        XCTAssertEqual(manager.currentThermalState, .serious)
        XCTAssertEqual(manager.effectiveFrameRate, 30)

        await manager.stopSession()
        XCTAssertFalse(manager.isRunning)
    }

    func testThermalThrottlingDropAndRestore() async throws {
        let manager = CaptureSessionManager()
        XCTAssertEqual(manager.effectiveFrameRate, 60)
        XCTAssertEqual(manager.currentThermalState, .nominal)

        // Drop 60fps -> 30fps on serious thermal state
        await manager.setThermalState(.serious)
        XCTAssertEqual(manager.currentThermalState, .serious)
        XCTAssertEqual(manager.effectiveFrameRate, 30)

        // Critical thermal state maintains 30fps
        await manager.setThermalState(.critical)
        XCTAssertEqual(manager.currentThermalState, .critical)
        XCTAssertEqual(manager.effectiveFrameRate, 30)

        // Cooled to fair restores 60fps
        await manager.setThermalState(.fair)
        XCTAssertEqual(manager.currentThermalState, .fair)
        XCTAssertEqual(manager.effectiveFrameRate, 60)

        // Nominal maintains 60fps
        await manager.setThermalState(.nominal)
        XCTAssertEqual(manager.currentThermalState, .nominal)
        XCTAssertEqual(manager.effectiveFrameRate, 60)
    }

    func testVideoSampleFramePassesMetadataAndBuffer() throws {
        let meta = CameraFrameMetadata(
            orientation: .up,
            iso: 400.0,
            shutterSpeedSeconds: 1.0 / 250.0,
            exposureBias: 0.5,
            lensAperture: 2.0,
            focalLengthMm: 35.0,
            hfovDeg: 63.4,
            intrinsicMatrix: [1, 0, 0, 0, 1, 0, 0, 0, 1],
            thermalState: .serious,
            rawExif: ["ISOSpeedRatings": "400", "ExposureTime": "0.004"]
        )

        let frame = VideoSampleFrame(
            presentationTimestamp: 42.0,
            width: 1920,
            height: 1080,
            pixelFormat: 0x34323066,
            isMock: false,
            pixelBuffer: nil,
            orientation: .up,
            metadata: meta
        )

        XCTAssertEqual(frame.presentationTimestamp, 42.0)
        XCTAssertEqual(frame.width, 1920)
        XCTAssertEqual(frame.height, 1080)
        XCTAssertEqual(frame.orientation, .up)
        XCTAssertEqual(frame.iso, 400.0)
        XCTAssertEqual(try XCTUnwrap(frame.shutterSpeedSeconds), 0.004, accuracy: 0.0001)
        XCTAssertEqual(frame.exposureBias, 0.5)
        XCTAssertEqual(frame.lensAperture, 2.0)
        XCTAssertEqual(frame.focalLengthMm, 35.0)
        XCTAssertEqual(try XCTUnwrap(frame.hfovDeg), 63.4, accuracy: 0.01)
        XCTAssertEqual(frame.intrinsicMatrix, [1, 0, 0, 0, 1, 0, 0, 0, 1])
        XCTAssertEqual(frame.thermalState, .serious)
        XCTAssertEqual(frame.rawExif["ISOSpeedRatings"], "400")
        XCTAssertNotNil(frame.ev)
    }

    func testPhotoCaptureController() async throws {
        let controller = CapturePhotoController()
        XCTAssertEqual(controller.captureAngle, 90.0)
        XCTAssertFalse(controller.isCapturing)

        let result = try await controller.capturePhoto()
        XCTAssertEqual(result.width, 5712)
        XCTAssertEqual(result.height, 4284)
        XCTAssertTrue(result.isDeferredProxy)

        let resultAngle = try await controller.capturePhoto(captureAngle: 180.0)
        XCTAssertEqual(resultAngle.width, 5712)

        let resultOrientation = try await controller.capturePhoto(orientation: .down)
        XCTAssertEqual(resultOrientation.width, 5712)

        // Cancel when no capture in progress is safe no-op
        controller.cancelActiveCapture()
        XCTAssertFalse(controller.isCapturing)

        XCTAssertEqual(CapturePhotoError.captureInProgress.errorDescription, "A photo capture request is already in progress.")
        XCTAssertEqual(CapturePhotoError.cancelled.errorDescription, "Photo capture was cancelled.")
    }

    func testVisionOrientationRoundingAndNormalization() {
        // Rounding: floating point angles near 90/180/270/0 degrees
        XCTAssertEqual(VisionOrientationMapper.visionOrientation(captureAngle: 89.9), .right)
        XCTAssertEqual(VisionOrientationMapper.visionOrientation(captureAngle: 90.1), .right)
        XCTAssertEqual(VisionOrientationMapper.visionOrientation(captureAngle: 179.8), .down)
        XCTAssertEqual(VisionOrientationMapper.visionOrientation(captureAngle: 180.2), .down)
        XCTAssertEqual(VisionOrientationMapper.visionOrientation(captureAngle: 269.9), .left)
        XCTAssertEqual(VisionOrientationMapper.visionOrientation(captureAngle: 270.1), .left)
        XCTAssertEqual(VisionOrientationMapper.visionOrientation(captureAngle: 359.9), .up)
        XCTAssertEqual(VisionOrientationMapper.visionOrientation(captureAngle: 0.1), .up)

        // Negative angles normalization
        XCTAssertEqual(VisionOrientationMapper.visionOrientation(captureAngle: -90.0), .left)
        XCTAssertEqual(VisionOrientationMapper.visionOrientation(captureAngle: -180.0), .down)
        XCTAssertEqual(VisionOrientationMapper.visionOrientation(captureAngle: -270.0), .right)
        XCTAssertEqual(VisionOrientationMapper.visionOrientation(captureAngle: -360.0), .up)

        // Angles > 360 degrees
        XCTAssertEqual(VisionOrientationMapper.visionOrientation(captureAngle: 450.0), .right)
        XCTAssertEqual(VisionOrientationMapper.visionOrientation(captureAngle: 540.0), .down)
        XCTAssertEqual(VisionOrientationMapper.visionOrientation(captureAngle: 630.0), .left)
        XCTAssertEqual(VisionOrientationMapper.visionOrientation(captureAngle: 720.0), .up)

        // NaN and Infinity edge cases
        XCTAssertEqual(VisionOrientationMapper.visionOrientation(captureAngle: .nan), .up)
        XCTAssertEqual(VisionOrientationMapper.visionOrientation(captureAngle: .infinity), .up)

        // captureAngle(for:) reverse mapping
        XCTAssertEqual(VisionOrientationMapper.captureAngle(for: .right), 90.0)
        XCTAssertEqual(VisionOrientationMapper.captureAngle(for: .down), 180.0)
        XCTAssertEqual(VisionOrientationMapper.captureAngle(for: .left), 270.0)
        XCTAssertEqual(VisionOrientationMapper.captureAngle(for: .up), 0.0)
    }

    private final class AngleBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _angles: [RotationAngles] = []
        var angles: [RotationAngles] {
            lock.lock()
            defer { lock.unlock() }
            return _angles
        }
        func append(_ a: RotationAngles) {
            lock.lock()
            defer { lock.unlock() }
            _angles.append(a)
        }
    }

    func testRotationCoordinatorAnglesAndOrientations() {
        let bridge = RotationCoordinatorBridge(initialAngles: .portrait)
        let angleBox = AngleBox()

        bridge.onAnglesChanged = { angles in
            angleBox.append(angles)
        }

        XCTAssertEqual(bridge.currentAngles.captureAngleDeg, 90.0)
        XCTAssertEqual(bridge.visionOrientation, .right)

        bridge.update(previewAngle: 0.0, captureAngle: 0.0)
        XCTAssertEqual(bridge.visionOrientation, .up)

        bridge.update(previewAngle: 180.0, captureAngle: 180.0)
        XCTAssertEqual(bridge.visionOrientation, .down)

        bridge.update(previewAngle: 270.0, captureAngle: 270.0)
        XCTAssertEqual(bridge.visionOrientation, .left)

        let history = angleBox.angles
        XCTAssertEqual(history.count, 3)
        XCTAssertEqual(history[0].captureAngleDeg, 0.0)
        XCTAssertEqual(history[1].captureAngleDeg, 180.0)
        XCTAssertEqual(history[2].captureAngleDeg, 270.0)

        bridge.stopObserving()
        XCTAssertFalse(bridge.isObserving)
    }

    func testCoordinateTransforms() {
        let visionPoint = CGPoint(x: 0.3, y: 0.8)
        let uiPoint = VisionOrientationMapper.pointFromVisionToUI(visionPoint)
        XCTAssertEqual(uiPoint.x, 0.3, accuracy: 0.0001)
        XCTAssertEqual(uiPoint.y, 0.2, accuracy: 0.0001)

        let visionRect = CGRect(x: 0.1, y: 0.2, width: 0.4, height: 0.5)
        let uiRect = VisionOrientationMapper.rectFromVisionToUI(visionRect)
        XCTAssertEqual(uiRect.origin.x, 0.1, accuracy: 0.0001)
        XCTAssertEqual(uiRect.origin.y, 0.3, accuracy: 0.0001) // 1.0 - (0.2 + 0.5) = 0.3
        XCTAssertEqual(uiRect.width, 0.4, accuracy: 0.0001)
        XCTAssertEqual(uiRect.height, 0.5, accuracy: 0.0001)
    }

    func testAspectFitViewportMapping() {
        let container = CGRect(x: 0, y: 0, width: 400, height: 800) // 1:2 aspect container
        let normalized = CGRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0)
        let fitted = VisionOrientationMapper.mapNormalizedRectToAspectFit(
            normalizedRect: normalized,
            containerBounds: container,
            contentAspectRatio: 4.0 / 3.0
        )
        // Container is 400x800 (taller than 4:3).
        // Fitted width = 400. Fitted height = 400 / (4/3) = 300.
        // offsetY = (800 - 300) / 2 = 250.
        XCTAssertEqual(fitted.origin.x, 0.0, accuracy: 0.001)
        XCTAssertEqual(fitted.origin.y, 250.0, accuracy: 0.001)
        XCTAssertEqual(fitted.width, 400.0, accuracy: 0.001)
        XCTAssertEqual(fitted.height, 300.0, accuracy: 0.001)
    }
}
