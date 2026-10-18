import XCTest
@testable import SyncKit

final class SyncKitTests: XCTestCase {
    func testNormalizedRectCenterCalculation() {
        let rect = NormalizedRect(x: 0.1, y: 0.2, width: 0.4, height: 0.6)
        let center = rect.center
        XCTAssertEqual(center.x, 0.3, accuracy: 0.0001)
        XCTAssertEqual(center.y, 0.5, accuracy: 0.0001)
    }

    func testSyncStatusEnum() {
        XCTAssertEqual(SyncStatus.pending.rawValue, "pending")
        XCTAssertEqual(SyncStatus.captured.rawValue, "captured")
        XCTAssertEqual(SyncStatus.syncing.rawValue, "syncing")
        XCTAssertEqual(SyncStatus.completed.rawValue, "completed")
        XCTAssertEqual(SyncStatus.expired.rawValue, "expired")
    }

    func testEncryptionEnvelopeCodableRoundtrip() throws {
        let envelope = EncryptionEnvelope(
            keyId: "key-123",
            nonceBase64: "bm9uY2U=",
            ciphertext: Data("encrypted".utf8),
            tagBase64: "dGFn"
        )
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(EncryptionEnvelope.self, from: data)
        XCTAssertEqual(envelope, decoded)
    }

    func testReferencePackageLifecycleAndExpiration() {
        let now = Date().timeIntervalSince1970
        let targetFraming = NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
        let activePackage = ReferencePackage(
            ownerDeviceToken: "device-token-abc",
            promptKey: "rule_of_thirds",
            targetFraming: targetFraming,
            compositionType: "portrait",
            createdTimestamp: now,
            expiresTimestamp: now + 300.0
        )
        XCTAssertFalse(activePackage.isExpired)

        let expiredPackage = ReferencePackage(
            ownerDeviceToken: "device-token-abc",
            promptKey: "rule_of_thirds",
            targetFraming: targetFraming,
            compositionType: "portrait",
            createdTimestamp: now - 600.0,
            expiresTimestamp: now - 1.0
        )
        XCTAssertTrue(expiredPackage.isExpired)
    }

    func testCapturePackageCodableRoundtrip() throws {
        let capture = CapturePackage(
            sessionId: UUID(),
            capturedPhotoJpeg: Data([0xFF, 0xD8, 0xFF, 0xE0]),
            cameraPitch: 1.5,
            cameraRoll: -0.5,
            focalLengthMm: 24.0,
            capturedTimestamp: 1000.0,
            clientNonce: "nonce-xyz"
        )
        let data = try JSONEncoder().encode(capture)
        let decoded = try JSONDecoder().decode(CapturePackage.self, from: data)
        XCTAssertEqual(capture, decoded)
    }
}
