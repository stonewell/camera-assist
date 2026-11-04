import Foundation

#if canImport(CryptoKit)
import CryptoKit
#endif

/// Cryptographic errors for SyncKit E2EE and session handshakes.
public enum CryptoError: Error, Equatable, Sendable {
    case cryptoKitUnavailable
    case invalidKeySize(expected: Int, actual: Int)
    case invalidPublicKey
    case keyAgreementFailed(String)
    case hkdfFailed(String)
    case encryptionFailed(String)
    case decryptionFailed(String)
    case authenticationFailed
    case invalidEnvelope
    case invalidURLFragment
    case tokenTampered
    case tokenExpired
}

/// Abstract E2EE cipher interface so transports and sessions are testable on any platform.
public protocol E2EECipher: Sendable {
    func encrypt(data: Data, key: Data, keyId: String) throws -> EncryptionEnvelope
    func decrypt(envelope: EncryptionEnvelope, key: Data) throws -> Data
}

extension E2EECipher {
    public func encryptPackage<T: Encodable>(_ item: T, key: Data, keyId: String = "") throws -> EncryptionEnvelope {
        let encoder = JSONEncoder()
        let data: Data
        do {
            data = try encoder.encode(item)
        } catch {
            throw CryptoError.encryptionFailed("JSON encoding failed: \(error)")
        }
        return try encrypt(data: data, key: key, keyId: keyId)
    }

    public func decryptPackage<T: Decodable>(_ type: T.Type, from envelope: EncryptionEnvelope, key: Data) throws -> T {
        let plaintext = try decrypt(envelope: envelope, key: key)
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(type, from: plaintext)
        } catch {
            throw CryptoError.decryptionFailed("JSON decoding failed: \(error)")
        }
    }

    public func encryptReferencePackage(_ package: ReferencePackage, key: Data, keyId: String = "") throws -> EncryptionEnvelope {
        try encryptPackage(package, key: key, keyId: keyId)
    }

    public func decryptReferencePackage(from envelope: EncryptionEnvelope, key: Data) throws -> ReferencePackage {
        try decryptPackage(ReferencePackage.self, from: envelope, key: key)
    }

    public func encryptCapturePackage(_ package: CapturePackage, key: Data, keyId: String = "") throws -> EncryptionEnvelope {
        try encryptPackage(package, key: key, keyId: keyId)
    }

    public func decryptCapturePackage(from envelope: EncryptionEnvelope, key: Data) throws -> CapturePackage {
        try decryptPackage(CapturePackage.self, from: envelope, key: key)
    }
}

/// Portable test cipher conforming to E2EECipher with authentication tag verification.
/// Used on platforms where CryptoKit is not imported (e.g. Linux test runner) or in synthetic tests.
public struct MockE2EECipher: E2EECipher, Sendable {
    public init() {}

    public func encrypt(data: Data, key: Data, keyId: String = "") throws -> EncryptionEnvelope {
        guard key.count >= 16 else {
            throw CryptoError.invalidKeySize(expected: 32, actual: key.count)
        }
        var nonceBytes = [UInt8](repeating: 0, count: 12)
        for i in 0..<12 {
            nonceBytes[i] = UInt8((i * 17 + 101) & 0xff)
        }
        let nonceData = Data(nonceBytes)

        var ciphertextBytes = [UInt8](repeating: 0, count: data.count)
        let keyBytes = [UInt8](key)
        let dataBytes = [UInt8](data)
        for i in 0..<data.count {
            let k = keyBytes[i % keyBytes.count]
            let n = nonceBytes[i % nonceBytes.count]
            ciphertextBytes[i] = dataBytes[i] ^ k ^ n
        }
        let ciphertext = Data(ciphertextBytes)

        // Compute HMAC-SHA256 authentication tag over key + nonce + ciphertext
        var tagInput = nonceData
        tagInput.append(ciphertext)
        let tagData = PureSwiftHMACSHA256.authenticate(key: key, data: tagInput)

        return EncryptionEnvelope(
            keyId: keyId,
            nonceBase64: nonceData.base64EncodedString(),
            ciphertext: ciphertext,
            tagBase64: tagData.prefix(16).base64EncodedString()
        )
    }

    public func decrypt(envelope: EncryptionEnvelope, key: Data) throws -> Data {
        guard key.count >= 16 else {
            throw CryptoError.invalidKeySize(expected: 32, actual: key.count)
        }
        guard let nonceData = Data(base64Encoded: envelope.nonceBase64),
              let tagData = Data(base64Encoded: envelope.tagBase64) else {
            throw CryptoError.invalidEnvelope
        }

        var tagInput = nonceData
        tagInput.append(envelope.ciphertext)
        let expectedTag = PureSwiftHMACSHA256.authenticate(key: key, data: tagInput).prefix(16)

        guard expectedTag == tagData else {
            throw CryptoError.authenticationFailed
        }

        let nonceBytes = [UInt8](nonceData)
        let keyBytes = [UInt8](key)
        let cipherBytes = [UInt8](envelope.ciphertext)
        var plaintextBytes = [UInt8](repeating: 0, count: cipherBytes.count)

        for i in 0..<cipherBytes.count {
            let k = keyBytes[i % keyBytes.count]
            let n = nonceBytes[i % nonceBytes.count]
            plaintextBytes[i] = cipherBytes[i] ^ k ^ n
        }

        return Data(plaintextBytes)
    }
}

#if canImport(CryptoKit)
/// Production CryptoKit AES-256-GCM Authenticated Encryption cipher.
public struct CryptoKitCipher: E2EECipher, Sendable {
    public init() {}

    public func encrypt(data: Data, key: Data, keyId: String = "") throws -> EncryptionEnvelope {
        guard key.count == 32 else {
            throw CryptoError.invalidKeySize(expected: 32, actual: key.count)
        }
        let symKey = SymmetricKey(data: key)
        do {
            let sealed = try AES.GCM.seal(data, using: symKey)
            let nonceBase64 = Data(sealed.nonce).base64EncodedString()
            let tagBase64 = sealed.tag.base64EncodedString()
            return EncryptionEnvelope(
                keyId: keyId,
                nonceBase64: nonceBase64,
                ciphertext: sealed.ciphertext,
                tagBase64: tagBase64
            )
        } catch {
            throw CryptoError.encryptionFailed(error.localizedDescription)
        }
    }

    public func decrypt(envelope: EncryptionEnvelope, key: Data) throws -> Data {
        guard key.count == 32 else {
            throw CryptoError.invalidKeySize(expected: 32, actual: key.count)
        }
        guard let nonceData = Data(base64Encoded: envelope.nonceBase64),
              let tagData = Data(base64Encoded: envelope.tagBase64) else {
            throw CryptoError.invalidEnvelope
        }
        let symKey = SymmetricKey(data: key)
        do {
            let nonce = try AES.GCM.Nonce(data: nonceData)
            let sealedBox = try AES.GCM.SealedBox(
                nonce: nonce,
                ciphertext: envelope.ciphertext,
                tag: tagData
            )
            return try AES.GCM.open(sealedBox, using: symKey)
        } catch {
            throw CryptoError.authenticationFailed
        }
    }
}

/// Curve25519 Key Agreement + HKDF-SHA256 session key negotiation.
public struct Curve25519KeyExchange: Sendable {
    public let privateKey: Curve25519.KeyAgreement.PrivateKey

    public var publicKey: Curve25519.KeyAgreement.PublicKey {
        privateKey.publicKey
    }

    public var publicKeyRaw: Data {
        publicKey.rawRepresentation
    }

    public var publicKeyBase64: String {
        publicKeyRaw.base64EncodedString()
    }

    public init() {
        self.privateKey = Curve25519.KeyAgreement.PrivateKey()
    }

    public init(privateKey: Curve25519.KeyAgreement.PrivateKey) {
        self.privateKey = privateKey
    }

    /// Derives a 256-bit symmetric key using Curve25519 ECDH + HKDF-SHA256.
    public func deriveSharedSymmetricKey(
        peerPublicKeyRaw: Data,
        salt: Data = Data("camera-assist-salt".utf8),
        sharedInfo: Data = Data("camera-assist-hkdf-info".utf8)
    ) throws -> Data {
        guard peerPublicKeyRaw.count == 32 else {
            throw CryptoError.invalidPublicKey
        }
        let peerKey: Curve25519.KeyAgreement.PublicKey
        do {
            peerKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPublicKeyRaw)
        } catch {
            throw CryptoError.invalidPublicKey
        }

        do {
            let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: peerKey)
            let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
                using: SHA256.self,
                salt: salt,
                sharedInfo: sharedInfo,
                outputByteCount: 32
            )
            return symmetricKey.withUnsafeBytes { Data($0) }
        } catch {
            throw CryptoError.keyAgreementFailed(error.localizedDescription)
        }
    }
}
#endif

#if canImport(CryptoKit)
public typealias DefaultE2EECipher = CryptoKitCipher
#else
public typealias DefaultE2EECipher = MockE2EECipher
#endif

/// URL Fragment Key Encoder & Parser for zero-knowledge cloud relay and App Clip Universal Links.
/// Key is stored in URL fragment (`#k=...`), so it is never sent in HTTP request headers or logged on server.
public struct URLFragmentKey: Sendable {
    public static func generateRandomKey() -> Data {
        #if canImport(CryptoKit)
        let key = SymmetricKey(size: .bits256)
        return key.withUnsafeBytes { Data($0) }
        #else
        var rng = SystemRandomNumberGenerator()
        var bytes = [UInt8](repeating: 0, count: 32)
        for i in 0..<32 {
            bytes[i] = UInt8.random(in: 0...255, using: &rng)
        }
        return Data(bytes)
        #endif
    }

    public static func encodeKeyToFragment(_ key: Data) -> String {
        let base64url = key.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "k=\(base64url)"
    }

    public static func decodeKeyFromFragment(_ fragment: String) throws -> Data {
        var base64: String
        if fragment.hasPrefix("k=") {
            base64 = String(fragment.dropFirst(2))
        } else {
            base64 = fragment
        }
        base64 = base64
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        guard let data = Data(base64Encoded: base64), data.count == 32 else {
            throw CryptoError.invalidURLFragment
        }
        return data
    }

    public static func buildUniversalLink(
        baseURL: URL,
        sessionId: UUID,
        token: String,
        key: Data
    ) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        components.queryItems = [
            URLQueryItem(name: "s", value: sessionId.uuidString),
            URLQueryItem(name: "t", value: token)
        ]
        components.fragment = encodeKeyToFragment(key)
        return components.url ?? baseURL
    }

    public static func parseUniversalLink(_ url: URL) throws -> (sessionId: UUID, token: String, key: Data) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw CryptoError.invalidURLFragment
        }
        guard let sVal = components.queryItems?.first(where: { $0.name == "s" })?.value,
              let sessionId = UUID(uuidString: sVal),
              let token = components.queryItems?.first(where: { $0.name == "t" })?.value else {
            throw CryptoError.invalidURLFragment
        }
        guard let fragment = components.fragment else {
            throw CryptoError.invalidURLFragment
        }
        let key = try decodeKeyFromFragment(fragment)
        return (sessionId, token, key)
    }
}
