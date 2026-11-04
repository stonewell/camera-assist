import Foundation

/// Errors encountered during SyncSession orchestration.
public enum SyncError: Error, Equatable, Sendable {
    case sessionExpired
    case handshakeFailed(String)
    case packageExpired
    case invalidState(String)
    case unexpectedMessage(String)
    case transportClosed
}

/// High-level session coordinator managing the lifecycle of an ephemeral camera-assist sharing session.
/// Enforces Curve25519 / AES-GCM E2EE, 10-minute session TTL self-destruction, and short-lived token auth.
public actor SyncSession {
    public let sessionId: UUID
    public let role: SessionRole
    public let transport: any SyncTransport
    public let cipher: any E2EECipher

    public private(set) var sessionKey: Data
    public private(set) var status: SyncStatus = .pending
    public let createdAt: Date
    public let expiresAt: Date

    public init(
        sessionId: UUID = UUID(),
        role: SessionRole,
        transport: any SyncTransport,
        cipher: any E2EECipher = DefaultE2EECipher(),
        sessionKey: Data,
        ttlSeconds: Double = 600.0
    ) {
        self.sessionId = sessionId
        self.role = role
        self.transport = transport
        self.cipher = cipher
        self.sessionKey = sessionKey
        self.createdAt = Date()
        self.expiresAt = Date().addingTimeInterval(ttlSeconds)
    }

    public var isExpired: Bool {
        Date() > expiresAt
    }

    /// Checks expiration TTL and fails session if expired.
    private func checkExpiration() throws {
        if isExpired {
            status = .expired
            throw SyncError.sessionExpired
        }
    }

    /// Performs the connection and handshake phase.
    /// Guest sends handshake with token (and optional Curve25519 public key).
    /// Owner verifies token signature & TTL, responds with handshake ack.
    public func start(
        token: SessionToken,
        secretForTokenVerification: Data? = nil
    ) async throws {
        try checkExpiration()
        status = .connecting
        try await transport.connect()

        switch role {
        case .guest:
            let payload = HandshakePayload(
                sessionId: sessionId,
                token: token.toTokenString(),
                clientRole: .guest,
                publicKeyBase64: nil,
                timestamp: Date().timeIntervalSince1970
            )
            try await transport.send(message: .handshake(payload))

            let response = try await transport.receive()
            guard case .handshakeAck(let ack) = response else {
                status = .failed
                throw SyncError.unexpectedMessage("Expected HandshakeAck, got \(response)")
            }
            guard ack.accepted else {
                status = .failed
                throw SyncError.handshakeFailed(ack.errorMessage ?? "Rejected by owner")
            }
            status = .ready

        case .owner, .relay:
            let incoming = try await transport.receive()
            guard case .handshake(let handshake) = incoming else {
                status = .failed
                throw SyncError.unexpectedMessage("Expected Handshake, got \(incoming)")
            }

            guard handshake.sessionId == sessionId else {
                let ack = HandshakeAckPayload(sessionId: sessionId, status: .failed, accepted: false, errorMessage: "Session ID mismatch")
                try? await transport.send(message: .handshakeAck(ack))
                status = .failed
                throw SyncError.handshakeFailed("Session ID mismatch")
            }

            // Verify token
            do {
                _ = try SessionToken.fromTokenString(handshake.token, secret: secretForTokenVerification ?? sessionKey)
            } catch {
                let ack = HandshakeAckPayload(sessionId: sessionId, status: .failed, accepted: false, errorMessage: "Invalid or expired token: \(error)")
                try? await transport.send(message: .handshakeAck(ack))
                status = .failed
                throw SyncError.handshakeFailed("Invalid or expired token: \(error)")
            }

            let ack = HandshakeAckPayload(sessionId: sessionId, status: .ready, accepted: true, errorMessage: nil)
            try await transport.send(message: .handshakeAck(ack))
            status = .ready
        }
    }

    #if canImport(CryptoKit)
    /// Advanced handshake performing Curve25519 key agreement + HKDF-SHA256 to derive a shared session key.
    public func startWithCurve25519KeyExchange(
        token: SessionToken,
        keyExchange: Curve25519KeyExchange,
        secretForTokenVerification: Data? = nil
    ) async throws {
        try checkExpiration()
        status = .connecting
        try await transport.connect()

        switch role {
        case .guest:
            let payload = HandshakePayload(
                sessionId: sessionId,
                token: token.toTokenString(),
                clientRole: .guest,
                publicKeyBase64: keyExchange.publicKeyBase64,
                timestamp: Date().timeIntervalSince1970
            )
            try await transport.send(message: .handshake(payload))

            let response = try await transport.receive()
            guard case .handshakeAck(let ack) = response else {
                status = .failed
                throw SyncError.unexpectedMessage("Expected HandshakeAck, got \(response)")
            }
            guard ack.accepted, let ownerPkBase64 = ack.publicKeyBase64,
                  let ownerPkRaw = Data(base64Encoded: ownerPkBase64) else {
                status = .failed
                throw SyncError.handshakeFailed(ack.errorMessage ?? "Missing owner public key")
            }

            // Derive shared key using Curve25519 + HKDF-SHA256 with sessionId as salt
            let salt = withUnsafeBytes(of: sessionId) { Data($0) }
            self.sessionKey = try keyExchange.deriveSharedSymmetricKey(peerPublicKeyRaw: ownerPkRaw, salt: salt)
            status = .ready

        case .owner, .relay:
            let incoming = try await transport.receive()
            guard case .handshake(let handshake) = incoming else {
                status = .failed
                throw SyncError.unexpectedMessage("Expected Handshake, got \(incoming)")
            }

            guard handshake.sessionId == sessionId else {
                let ack = HandshakeAckPayload(sessionId: sessionId, status: .failed, accepted: false, errorMessage: "Session ID mismatch")
                try? await transport.send(message: .handshakeAck(ack))
                status = .failed
                throw SyncError.handshakeFailed("Session ID mismatch")
            }

            // Verify token
            do {
                _ = try SessionToken.fromTokenString(handshake.token, secret: secretForTokenVerification ?? sessionKey)
            } catch {
                let ack = HandshakeAckPayload(sessionId: sessionId, status: .failed, accepted: false, errorMessage: "Invalid or expired token")
                try? await transport.send(message: .handshakeAck(ack))
                status = .failed
                throw SyncError.handshakeFailed("Invalid or expired token")
            }

            guard let guestPkBase64 = handshake.publicKeyBase64,
                  let guestPkRaw = Data(base64Encoded: guestPkBase64) else {
                let ack = HandshakeAckPayload(sessionId: sessionId, status: .failed, accepted: false, errorMessage: "Missing guest public key")
                try? await transport.send(message: .handshakeAck(ack))
                status = .failed
                throw SyncError.handshakeFailed("Missing guest public key")
            }

            // Derive shared key using Curve25519 + HKDF-SHA256 with sessionId as salt
            let salt = withUnsafeBytes(of: sessionId) { Data($0) }
            self.sessionKey = try keyExchange.deriveSharedSymmetricKey(peerPublicKeyRaw: guestPkRaw, salt: salt)

            let ack = HandshakeAckPayload(
                sessionId: sessionId,
                status: .ready,
                publicKeyBase64: keyExchange.publicKeyBase64,
                accepted: true,
                errorMessage: nil
            )
            try await transport.send(message: .handshakeAck(ack))
            status = .ready
        }
    }
    #endif

    /// Owner sends encrypted ReferencePackage to guest device.
    public func sendReferencePackage(_ package: ReferencePackage) async throws {
        try checkExpiration()
        guard status == .ready || status == .connecting else {
            throw SyncError.invalidState("Cannot send ReferencePackage in state \(status)")
        }
        let envelope = try cipher.encryptReferencePackage(package, key: sessionKey)
        try await transport.send(message: .referencePackageEnvelope(envelope))
        status = .syncing
    }

    /// Guest waits for and decrypts ReferencePackage from owner device.
    public func receiveReferencePackage() async throws -> ReferencePackage {
        try checkExpiration()
        let msg = try await transport.receive()
        guard case .referencePackageEnvelope(let envelope) = msg else {
            throw SyncError.unexpectedMessage("Expected ReferencePackageEnvelope, got \(msg)")
        }
        let package = try cipher.decryptReferencePackage(from: envelope, key: sessionKey)
        if package.isExpired {
            status = .expired
            throw SyncError.packageExpired
        }
        status = .syncing
        return package
    }

    /// Guest sends photographic CapturePackage back to owner device.
    public func sendCapturePackage(_ package: CapturePackage) async throws {
        try checkExpiration()
        let envelope = try cipher.encryptCapturePackage(package, key: sessionKey)
        try await transport.send(message: .capturePackageEnvelope(envelope))
        status = .completed
    }

    /// Owner waits for and decrypts CapturePackage returned by guest camera.
    public func receiveCapturePackage() async throws -> CapturePackage {
        try checkExpiration()
        let msg = try await transport.receive()
        guard case .capturePackageEnvelope(let envelope) = msg else {
            throw SyncError.unexpectedMessage("Expected CapturePackageEnvelope, got \(msg)")
        }
        let package = try cipher.decryptCapturePackage(from: envelope, key: sessionKey)
        status = .completed
        return package
    }

    /// Closes session and underlying transport channel.
    public func close() async {
        status = .completed
        await transport.close()
    }
}
