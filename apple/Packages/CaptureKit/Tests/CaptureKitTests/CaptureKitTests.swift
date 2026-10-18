import XCTest
@testable import CaptureKit

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

        await manager.setThermalState(.serious)
        XCTAssertEqual(manager.currentThermalState, .serious)

        await manager.stopSession()
        XCTAssertFalse(manager.isRunning)
    }

    func testPhotoCaptureController() async throws {
        let controller = CapturePhotoController()
        let result = try await controller.capturePhoto()
        XCTAssertEqual(result.width, 5712)
        XCTAssertEqual(result.height, 4284)
        XCTAssertTrue(result.isDeferredProxy)
    }

    func testRotationCoordinatorAnglesAndOrientations() {
        let bridge = RotationCoordinatorBridge(initialAngles: .portrait)
        XCTAssertEqual(bridge.currentAngles.captureAngleDeg, 90.0)
        XCTAssertEqual(bridge.visionOrientation, .right)

        bridge.update(previewAngle: 0.0, captureAngle: 0.0)
        XCTAssertEqual(bridge.visionOrientation, .up)

        bridge.update(previewAngle: 180.0, captureAngle: 180.0)
        XCTAssertEqual(bridge.visionOrientation, .down)

        bridge.update(previewAngle: 270.0, captureAngle: 270.0)
        XCTAssertEqual(bridge.visionOrientation, .left)
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
