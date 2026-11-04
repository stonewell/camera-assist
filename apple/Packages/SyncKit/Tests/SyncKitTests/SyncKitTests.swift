import XCTest
@testable import SyncKit

#if canImport(CryptoKit)
import CryptoKit
#endif

final class SyncKitTests: XCTestCase {

    // MARK: - Baseline Tests (Preserved)

    func testNormalizedRectCenterCalculation() {
        let rect = NormalizedRect(x: 0.1, y: 0.2, width: 0.4, height: 0.6)
        let center = rect.center
        XCTAssertEqual(center.x, 0.3, accuracy: 0.0001)
        XCTAssertEqual(center.y, 0.5, accuracy: 0.0001)
    }

    func testSyncStatusEnum() {
        XCTAssertEqual(SyncStatus.pending.rawValue, "pending")
        XCTAssertEqual(SyncStatus.connecting.rawValue, "connecting")
        XCTAssertEqual(SyncStatus.ready.rawValue, "ready")
        XCTAssertEqual(SyncStatus.captured.rawValue, "captured")
        XCTAssertEqual(SyncStatus.syncing.rawValue, "syncing")
        XCTAssertEqual(SyncStatus.completed.rawValue, "completed")
        XCTAssertEqual(SyncStatus.expired.rawValue, "expired")
        XCTAssertEqual(SyncStatus.failed.rawValue, "failed")
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

    // MARK: - Extended Data Contract & Plan Tests

    func testAlignmentOffsetCalculations() {
        let offset = AlignmentOffset(dx: 12.5, dy: -8.0)
        XCTAssertEqual(offset.dx, 12.5)
        XCTAssertEqual(offset.dy, -8.0)

        #if canImport(CoreGraphics)
        let cgVector = offset.cgVector
        XCTAssertEqual(Double(cgVector.dx), 12.5)
        XCTAssertEqual(Double(cgVector.dy), -8.0)

        let roundtrip = AlignmentOffset(cgVector: cgVector)
        XCTAssertEqual(roundtrip, offset)
        #endif
    }

    func testReferencePackageFullPlanFieldsRoundtrip() throws {
        let sessionId = UUID()
        let slot1 = NormalizedRect(x: 0.2, y: 0.2, width: 0.3, height: 0.6)
        let slot2 = NormalizedRect(x: 0.6, y: 0.2, width: 0.3, height: 0.6)

        let package = ReferencePackage(
            sessionId: sessionId,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(600.0),
            ownerDeviceToken: "owner-device-token-123",
            promptKey: "stranger.align_ghost",
            targetFraming: NormalizedRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
            compositionType: "two_person_portrait",
            thumbnailJpegData: Data([0x01, 0x02, 0x03]),
            registrationGrayData: Data([0xAA, 0xBB, 0xCC]),
            targetZoomFactor: 2.0,
            captureAngle: 90.0,
            elevationDeg: 5.0,
            rollDeg: -1.2,
            slots: [slot1, slot2],
            languageCode: "ja",
            autoBurstEnabled: true,
            previewThumbnailData: Data([0x01, 0x02, 0x03])
        )

        let data = try JSONEncoder().encode(package)
        let decoded = try JSONDecoder().decode(ReferencePackage.self, from: data)

        XCTAssertEqual(decoded.sessionId, sessionId)
        XCTAssertEqual(decoded.promptKey, "stranger.align_ghost")
        XCTAssertEqual(decoded.targetZoomFactor, 2.0)
        XCTAssertEqual(decoded.captureAngle, 90.0)
        XCTAssertEqual(decoded.elevationDeg, 5.0)
        XCTAssertEqual(decoded.rollDeg, -1.2)
        XCTAssertEqual(decoded.slots.count, 2)
        XCTAssertEqual(decoded.slots[0], slot1)
        XCTAssertEqual(decoded.languageCode, "ja")
        XCTAssertTrue(decoded.autoBurstEnabled)
        XCTAssertEqual(decoded.thumbnailJpegData, Data([0x01, 0x02, 0x03]))
        XCTAssertEqual(decoded.registrationGrayData, Data([0xAA, 0xBB, 0xCC]))
        XCTAssertFalse(decoded.isExpired)
    }

    func testCapturePackageFullPlanFieldsRoundtrip() throws {
        let sessionId = UUID()
        let photoId = "photo-uuid-456"
        let fullPhotoData = Data([0xFF, 0xD8, 0xFF, 0xE1, 0x00, 0x18])
        let thumbData = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let offset = AlignmentOffset(dx: 0.02, dy: -0.01)

        let capture = CapturePackage(
            sessionId: sessionId,
            photoId: photoId,
            sequenceIndex: 2,
            capturedAt: Date(),
            fullPhotoData: fullPhotoData,
            previewThumbnailData: thumbData,
            alignmentOffset: offset,
            alignmentScale: 1.05,
            wasReadyState: true,
            deviceModel: "iPhone 15 Pro",
            cameraPitch: 3.2,
            cameraRoll: -0.8,
            focalLengthMm: 77.0,
            clientNonce: "nonce-xyz-789"
        )

        let data = try JSONEncoder().encode(capture)
        let decoded = try JSONDecoder().decode(CapturePackage.self, from: data)

        XCTAssertEqual(decoded.sessionId, sessionId)
        XCTAssertEqual(decoded.photoId, photoId)
        XCTAssertEqual(decoded.sequenceIndex, 2)
        XCTAssertEqual(decoded.fullPhotoData, fullPhotoData)
        XCTAssertEqual(decoded.capturedPhotoJpeg, fullPhotoData)
        XCTAssertEqual(decoded.previewThumbnailData, thumbData)
        XCTAssertEqual(decoded.alignmentOffset, offset)
        XCTAssertEqual(decoded.alignmentScale, 1.05)
        XCTAssertTrue(decoded.wasReadyState)
        XCTAssertEqual(decoded.deviceModel, "iPhone 15 Pro")
        XCTAssertEqual(decoded.cameraPitch, 3.2)
        XCTAssertEqual(decoded.cameraRoll, -0.8)
        XCTAssertEqual(decoded.focalLengthMm, 77.0)
        XCTAssertEqual(decoded.clientNonce, "nonce-xyz-789")
    }

    // MARK: - Short-Lived Token Auth & Tamper Rejection Tests

    func testSessionTokenGenerationAndVerification() throws {
        let sessionId = UUID()
        let secret = Data("shared-session-secret-key-32bytes".utf8)

        let token = SessionToken.generate(
            sessionId: sessionId,
            role: .guest,
            ttlSeconds: 600.0, // 10 minutes
            secret: secret,
            nonce: "test-nonce-123"
        )

        XCTAssertFalse(token.isExpired)
        XCTAssertTrue(token.isValid(forSession: sessionId, expectedRole: .guest))
        XCTAssertFalse(token.isValid(forSession: UUID(), expectedRole: .guest)) // wrong session
        XCTAssertFalse(token.isValid(forSession: sessionId, expectedRole: .owner)) // wrong role
        XCTAssertTrue(token.verify(secret: secret))

        // Rejection with wrong secret
        let wrongSecret = Data("wrong-secret-key-that-fails-123".utf8)
        XCTAssertFalse(token.verify(secret: wrongSecret))

        // Serialization and parsing roundtrip
        let tokenString = token.toTokenString()
        let parsedToken = try SessionToken.fromTokenString(tokenString, secret: secret)
        XCTAssertEqual(parsedToken.sessionId, sessionId)
        XCTAssertEqual(parsedToken.role, .guest)
        XCTAssertEqual(parsedToken.nonce, "test-nonce-123")
    }

    func testSessionTokenTamperRejection() throws {
        let sessionId = UUID()
        let secret = Data("super-secret-key-for-auth-token-1".utf8)

        var token = SessionToken.generate(
            sessionId: sessionId,
            role: .guest,
            ttlSeconds: 600.0,
            secret: secret
        )

        // Tamper with role
        token.role = .owner
        XCTAssertFalse(token.verify(secret: secret))

        // Tamper with sessionId
        token.sessionId = UUID()
        XCTAssertFalse(token.verify(secret: secret))

        // Tamper with expiration
        token.expiresAt += 3600.0
        XCTAssertFalse(token.verify(secret: secret))

        // Parsing tampered string fails
        let tamperedString = token.toTokenString()
        XCTAssertThrowsError(try SessionToken.fromTokenString(tamperedString, secret: secret)) { error in
            XCTAssertEqual(error as? CryptoError, CryptoError.tokenTampered)
        }
    }

    func testSessionTokenExpirationRejection() {
        let sessionId = UUID()
        let secret = Data("secret-for-expired-token-testing".utf8)

        let expiredToken = SessionToken(
            sessionId: sessionId,
            role: .guest,
            issuedAt: Date().timeIntervalSince1970 - 700.0,
            expiresAt: Date().timeIntervalSince1970 - 100.0, // expired
            nonce: "nonce",
            signature: "dummy"
        )
        XCTAssertTrue(expiredToken.isExpired)
        XCTAssertFalse(expiredToken.isValid)

        let tokenString = expiredToken.toTokenString()
        XCTAssertThrowsError(try SessionToken.fromTokenString(tokenString, secret: secret)) { error in
            XCTAssertEqual(error as? CryptoError, CryptoError.tokenExpired)
        }
    }

    // MARK: - URL Fragment Key & Universal Link Tests

    func testURLFragmentKeyEncodingAndDecoding() throws {
        let key = URLFragmentKey.generateRandomKey()
        XCTAssertEqual(key.count, 32)

        let fragment = URLFragmentKey.encodeKeyToFragment(key)
        XCTAssertTrue(fragment.hasPrefix("k="))

        let decodedKey = try URLFragmentKey.decodeKeyFromFragment(fragment)
        XCTAssertEqual(decodedKey, key)

        let rawFragment = String(fragment.dropFirst(2))
        let decodedKeyFromRaw = try URLFragmentKey.decodeKeyFromFragment(rawFragment)
        XCTAssertEqual(decodedKeyFromRaw, key)
    }

    func testUniversalLinkBuildingAndParsing() throws {
        let baseURL = URL(string: "https://camera-assist.app/clip")!
        let sessionId = UUID()
        let token = "test-token-string"
        let key = URLFragmentKey.generateRandomKey()

        let link = URLFragmentKey.buildUniversalLink(baseURL: baseURL, sessionId: sessionId, token: token, key: key)
        XCTAssertTrue(link.absoluteString.contains("s=\(sessionId.uuidString)"))
        XCTAssertTrue(link.absoluteString.contains("t=\(token)"))
        XCTAssertTrue(link.absoluteString.contains("#k="))

        let (parsedSessionId, parsedToken, parsedKey) = try URLFragmentKey.parseUniversalLink(link)
        XCTAssertEqual(parsedSessionId, sessionId)
        XCTAssertEqual(parsedToken, token)
        XCTAssertEqual(parsedKey, key)
    }

    // MARK: - In-Memory Transport & End-to-End Session Tests

    func testInMemoryTransportPairExchange() async throws {
        let (client, server) = InMemoryTransport.createPair()
        try await client.connect()
        try await server.connect()

        let payload = HandshakePayload(sessionId: UUID(), token: "tok-1", clientRole: .guest)
        try await client.send(message: .handshake(payload))

        let received = try await server.receive()
        guard case .handshake(let recPayload) = received else {
            XCTFail("Expected handshake message")
            return
        }
        XCTAssertEqual(recPayload.sessionId, payload.sessionId)
        XCTAssertEqual(recPayload.token, "tok-1")

        await client.close()
        await server.close()
    }

    func testSyncSessionEndToEndOwnerGuestExchange() async throws {
        let sessionId = UUID()
        let sessionKey = URLFragmentKey.generateRandomKey()
        let (ownerTransport, guestTransport) = InMemoryTransport.createPair()

        let ownerSession = SyncSession(
            sessionId: sessionId,
            role: .owner,
            transport: ownerTransport,
            cipher: MockE2EECipher(),
            sessionKey: sessionKey
        )

        let guestSession = SyncSession(
            sessionId: sessionId,
            role: .guest,
            transport: guestTransport,
            cipher: MockE2EECipher(),
            sessionKey: sessionKey
        )

        let guestToken = SessionToken.generate(
            sessionId: sessionId,
            role: .guest,
            ttlSeconds: 600.0,
            secret: sessionKey
        )

        // Handshake asynchronously
        async let ownerStart: Void = ownerSession.start(token: guestToken, secretForTokenVerification: sessionKey)
        async let guestStart: Void = guestSession.start(token: guestToken)
        _ = try await (ownerStart, guestStart)

        let ownerStatus = await ownerSession.status
        let guestStatus = await guestSession.status
        XCTAssertEqual(ownerStatus, .ready)
        XCTAssertEqual(guestStatus, .ready)

        // 1. Owner sends ReferencePackage
        let refPackage = ReferencePackage(
            sessionId: sessionId,
            ownerDeviceToken: "device-owner",
            promptKey: "rule_of_thirds",
            targetFraming: NormalizedRect(x: 0.15, y: 0.15, width: 0.7, height: 0.7),
            compositionType: "portrait",
            thumbnailJpegData: Data([0x11, 0x22]),
            targetZoomFactor: 1.5
        )

        async let ownerSendRef: Void = ownerSession.sendReferencePackage(refPackage)
        async let guestReceiveRef = guestSession.receiveReferencePackage()

        let (_, receivedRef) = try await (ownerSendRef, guestReceiveRef)
        XCTAssertEqual(receivedRef.sessionId, sessionId)
        XCTAssertEqual(receivedRef.targetZoomFactor, 1.5)
        XCTAssertEqual(receivedRef.thumbnailJpegData, Data([0x11, 0x22]))

        // 2. Guest sends CapturePackage
        let capPackage = CapturePackage(
            sessionId: sessionId,
            photoId: "photo-001",
            sequenceIndex: 0,
            capturedAt: Date(),
            fullPhotoData: Data([0x99, 0x88, 0x77]),
            previewThumbnailData: Data([0x99]),
            deviceModel: "iPhone 16 Pro"
        )

        async let guestSendCap: Void = guestSession.sendCapturePackage(capPackage)
        async let ownerReceiveCap = ownerSession.receiveCapturePackage()

        let (_, receivedCap) = try await (guestSendCap, ownerReceiveCap)
        XCTAssertEqual(receivedCap.sessionId, sessionId)
        XCTAssertEqual(receivedCap.photoId, "photo-001")
        XCTAssertEqual(receivedCap.fullPhotoData, Data([0x99, 0x88, 0x77]))
        XCTAssertEqual(receivedCap.deviceModel, "iPhone 16 Pro")

        await ownerSession.close()
        await guestSession.close()
    }

    func testTamperingRejectionWithMockCipher() throws {
        let cipher = MockE2EECipher()
        let key = URLFragmentKey.generateRandomKey()
        let originalData = Data("sensitive-camera-assist-photo-bytes".utf8)

        let envelope = try cipher.encrypt(data: originalData, key: key, keyId: "test-key")

        // 1. Decrypt clean envelope succeeds
        let decrypted = try cipher.decrypt(envelope: envelope, key: key)
        XCTAssertEqual(decrypted, originalData)

        // 2. Tampered ciphertext is rejected
        var tamperedCiphertext = envelope.ciphertext
        tamperedCiphertext[0] ^= 0xFF
        let tamperedEnvelope1 = EncryptionEnvelope(
            keyId: envelope.keyId,
            nonceBase64: envelope.nonceBase64,
            ciphertext: tamperedCiphertext,
            tagBase64: envelope.tagBase64
        )
        XCTAssertThrowsError(try cipher.decrypt(envelope: tamperedEnvelope1, key: key)) { error in
            XCTAssertEqual(error as? CryptoError, CryptoError.authenticationFailed)
        }

        // 3. Tampered tag is rejected
        let tamperedEnvelope2 = EncryptionEnvelope(
            keyId: envelope.keyId,
            nonceBase64: envelope.nonceBase64,
            ciphertext: envelope.ciphertext,
            tagBase64: "bm90X3ZhbGlkX3RhZw=="
        )
        XCTAssertThrowsError(try cipher.decrypt(envelope: tamperedEnvelope2, key: key)) { error in
            XCTAssertEqual(error as? CryptoError, CryptoError.authenticationFailed)
        }

        // 4. Decrypt with wrong key fails
        let wrongKey = URLFragmentKey.generateRandomKey()
        XCTAssertThrowsError(try cipher.decrypt(envelope: envelope, key: wrongKey)) { error in
            XCTAssertEqual(error as? CryptoError, CryptoError.authenticationFailed)
        }
    }

    func testTamperedTokenRejectionInHandshake() async throws {
        let sessionId = UUID()
        let correctKey = URLFragmentKey.generateRandomKey()
        let (ownerTransport, guestTransport) = InMemoryTransport.createPair()

        let ownerSession = SyncSession(
            sessionId: sessionId,
            role: .owner,
            transport: ownerTransport,
            cipher: MockE2EECipher(),
            sessionKey: correctKey
        )

        let guestSession = SyncSession(
            sessionId: sessionId,
            role: .guest,
            transport: guestTransport,
            cipher: MockE2EECipher(),
            sessionKey: correctKey
        )

        // Tampered token with forged signature
        let tamperedToken = SessionToken(
            sessionId: sessionId,
            role: .guest,
            issuedAt: Date().timeIntervalSince1970,
            expiresAt: Date().timeIntervalSince1970 + 600.0,
            nonce: "forged-nonce",
            signature: "forged-signature"
        )

        async let ownerStart: Void = ownerSession.start(token: tamperedToken, secretForTokenVerification: correctKey)
        async let guestStart: Void = guestSession.start(token: tamperedToken)

        do {
            _ = try await (ownerStart, guestStart)
            XCTFail("Handshake with tampered token must fail")
        } catch {
            // Expected failure
            XCTAssertTrue(error is SyncError)
        }

        await ownerSession.close()
        await guestSession.close()
    }

    // MARK: - CryptoKit Production E2EE Tests (Apple Platforms)

    #if canImport(CryptoKit)
    func testCryptoKitAESGCMEncryptDecrypt() throws {
        let cipher = CryptoKitCipher()
        let key = URLFragmentKey.generateRandomKey()
        XCTAssertEqual(key.count, 32)

        let refPackage = ReferencePackage(
            sessionId: UUID(),
            ownerDeviceToken: "token-abc",
            promptKey: "rule_of_thirds",
            targetFraming: NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6),
            compositionType: "portrait",
            thumbnailJpegData: Data([0xDE, 0xAD, 0xBE, 0xEF]),
            targetZoomFactor: 2.0
        )

        let envelope = try cipher.encryptReferencePackage(refPackage, key: key)
        XCTAssertFalse(envelope.ciphertext.isEmpty)
        XCTAssertFalse(envelope.nonceBase64.isEmpty)
        XCTAssertFalse(envelope.tagBase64.isEmpty)

        let decrypted = try cipher.decryptReferencePackage(from: envelope, key: key)
        XCTAssertEqual(decrypted.sessionId, refPackage.sessionId)
        XCTAssertEqual(decrypted.thumbnailJpegData, refPackage.thumbnailJpegData)
        XCTAssertEqual(decrypted.targetZoomFactor, 2.0)
    }

    func testCryptoKitAESGCMTamperDetection() throws {
        let cipher = CryptoKitCipher()
        let key = URLFragmentKey.generateRandomKey()
        let plaintext = Data("sensitive-travel-photo-data".utf8)

        let envelope = try cipher.encrypt(data: plaintext, key: key, keyId: "test-k")

        // Mutate ciphertext
        var tamperedCiphertext = envelope.ciphertext
        tamperedCiphertext[0] ^= 0x01
        let tamperedEnv1 = EncryptionEnvelope(
            keyId: envelope.keyId,
            nonceBase64: envelope.nonceBase64,
            ciphertext: tamperedCiphertext,
            tagBase64: envelope.tagBase64
        )
        XCTAssertThrowsError(try cipher.decrypt(envelope: tamperedEnv1, key: key)) { error in
            XCTAssertEqual(error as? CryptoError, CryptoError.authenticationFailed)
        }

        // Mutate auth tag
        var tagData = Data(base64Encoded: envelope.tagBase64)!
        tagData[0] ^= 0x01
        let tamperedEnv2 = EncryptionEnvelope(
            keyId: envelope.keyId,
            nonceBase64: envelope.nonceBase64,
            ciphertext: envelope.ciphertext,
            tagBase64: tagData.base64EncodedString()
        )
        XCTAssertThrowsError(try cipher.decrypt(envelope: tamperedEnv2, key: key)) { error in
            XCTAssertEqual(error as? CryptoError, CryptoError.authenticationFailed)
        }
    }

    func testCurve25519KeyAgreementAndHKDF() throws {
        let ownerExchange = Curve25519KeyExchange()
        let guestExchange = Curve25519KeyExchange()

        XCTAssertEqual(ownerExchange.publicKeyRaw.count, 32)
        XCTAssertEqual(guestExchange.publicKeyRaw.count, 32)

        let salt = Data("camera-assist-salt-001".utf8)
        let info = Data("camera-assist-info-001".utf8)

        // Both derive shared symmetric key independently
        let ownerDerivedKey = try ownerExchange.deriveSharedSymmetricKey(
            peerPublicKeyRaw: guestExchange.publicKeyRaw,
            salt: salt,
            sharedInfo: info
        )

        let guestDerivedKey = try guestExchange.deriveSharedSymmetricKey(
            peerPublicKeyRaw: ownerExchange.publicKeyRaw,
            salt: salt,
            sharedInfo: info
        )

        XCTAssertEqual(ownerDerivedKey.count, 32)
        XCTAssertEqual(guestDerivedKey.count, 32)
        XCTAssertEqual(ownerDerivedKey, guestDerivedKey, "Curve25519 ECDH + HKDF must produce identical keys")

        // Verify that the derived key encrypts and decrypts packages cleanly with AES-GCM
        let cipher = CryptoKitCipher()
        let cap = CapturePackage(
            sessionId: UUID(),
            photoId: "p1",
            fullPhotoData: Data([0x12, 0x34, 0x56]),
            previewThumbnailData: Data()
        )

        let env = try cipher.encryptCapturePackage(cap, key: guestDerivedKey)
        let decrypted = try cipher.decryptCapturePackage(from: env, key: ownerDerivedKey)
        XCTAssertEqual(decrypted.sessionId, cap.sessionId)
        XCTAssertEqual(decrypted.fullPhotoData, cap.fullPhotoData)
    }

    func testSyncSessionCurve25519KeyAgreementEndToEnd() async throws {
        let sessionId = UUID()
        let (ownerTransport, guestTransport) = InMemoryTransport.createPair()
        let tokenAuthSecret = Data("token-auth-secret-32bytes-long!!".utf8)

        let ownerSession = SyncSession(
            sessionId: sessionId,
            role: .owner,
            transport: ownerTransport,
            cipher: CryptoKitCipher(),
            sessionKey: Data() // will be established via Curve25519
        )

        let guestSession = SyncSession(
            sessionId: sessionId,
            role: .guest,
            transport: guestTransport,
            cipher: CryptoKitCipher(),
            sessionKey: Data() // will be established via Curve25519
        )

        let guestToken = SessionToken.generate(
            sessionId: sessionId,
            role: .guest,
            ttlSeconds: 600.0,
            secret: tokenAuthSecret
        )

        let ownerExchange = Curve25519KeyExchange()
        let guestExchange = Curve25519KeyExchange()

        async let ownerStart: Void = ownerSession.startWithCurve25519KeyExchange(
            token: guestToken,
            keyExchange: ownerExchange,
            secretForTokenVerification: tokenAuthSecret
        )
        async let guestStart: Void = guestSession.startWithCurve25519KeyExchange(
            token: guestToken,
            keyExchange: guestExchange,
            secretForTokenVerification: tokenAuthSecret
        )

        _ = try await (ownerStart, guestStart)

        let ownerStatus = await ownerSession.status
        let guestStatus = await guestSession.status
        XCTAssertEqual(ownerStatus, .ready)
        XCTAssertEqual(guestStatus, .ready)

        // Verify owner and guest negotiated identical non-empty keys
        let ownerKey = await ownerSession.sessionKey
        let guestKey = await guestSession.sessionKey
        XCTAssertEqual(ownerKey.count, 32)
        XCTAssertEqual(ownerKey, guestKey)

        // Send ReferencePackage from Owner to Guest
        let ref = ReferencePackage(
            sessionId: sessionId,
            ownerDeviceToken: "owner",
            promptKey: "rule_of_thirds",
            targetFraming: NormalizedRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
            compositionType: "portrait",
            thumbnailJpegData: Data([0xAA, 0xBB])
        )

        async let sendRef: Void = ownerSession.sendReferencePackage(ref)
        async let recvRef = guestSession.receiveReferencePackage()
        let (_, receivedRef) = try await (sendRef, recvRef)
        XCTAssertEqual(receivedRef.sessionId, sessionId)
        XCTAssertEqual(receivedRef.thumbnailJpegData, Data([0xAA, 0xBB]))

        // Send CapturePackage from Guest to Owner
        let cap = CapturePackage(
            sessionId: sessionId,
            photoId: "photo-curve25519",
            fullPhotoData: Data([0xCC, 0xDD, 0xEE]),
            deviceModel: "iPhone 16 Pro Max"
        )

        async let sendCap: Void = guestSession.sendCapturePackage(cap)
        async let recvCap = ownerSession.receiveCapturePackage()
        let (_, receivedCap) = try await (sendCap, recvCap)
        XCTAssertEqual(receivedCap.photoId, "photo-curve25519")
        XCTAssertEqual(receivedCap.deviceModel, "iPhone 16 Pro Max")

        await ownerSession.close()
        await guestSession.close()
    }
    #endif
}
