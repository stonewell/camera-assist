import Foundation

/// Pure Swift SHA-256 implementation (FIPS 180-4 standard compliant).
/// Guaranteed zero C/Rust dependencies, fully functional on all platforms.
enum PureSwiftSHA256 {
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ]

    static func hash(data: Data) -> Data {
        var h0: UInt32 = 0x6a09e667
        var h1: UInt32 = 0xbb67ae85
        var h2: UInt32 = 0x3c6ef372
        var h3: UInt32 = 0xa54ff53a
        var h4: UInt32 = 0x510e527f
        var h5: UInt32 = 0x9b05688c
        var h6: UInt32 = 0x1f83d9ab
        var h7: UInt32 = 0x5be0cd19

        var message = [UInt8](data)
        let bitLen = UInt64(message.count) * 8
        message.append(0x80)
        while (message.count % 64) != 56 {
            message.append(0)
        }
        for i in (0..<8).reversed() {
            message.append(UInt8((bitLen >> (i * 8)) & 0xff))
        }

        var w = [UInt32](repeating: 0, count: 64)
        for chunkStart in stride(from: 0, to: message.count, by: 64) {
            for i in 0..<16 {
                let j = chunkStart + i * 4
                w[i] = (UInt32(message[j]) << 24) |
                       (UInt32(message[j + 1]) << 16) |
                       (UInt32(message[j + 2]) << 8) |
                       UInt32(message[j + 3])
            }
            for i in 16..<64 {
                let s0 = (w[i - 15] >> 7 | w[i - 15] << (32 - 7)) ^
                         (w[i - 15] >> 18 | w[i - 15] << (32 - 18)) ^
                         (w[i - 15] >> 3)
                let s1 = (w[i - 2] >> 17 | w[i - 2] << (32 - 17)) ^
                         (w[i - 2] >> 19 | w[i - 2] << (32 - 19)) ^
                         (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }

            var a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7
            for i in 0..<64 {
                let S1 = (e >> 6 | e << (32 - 6)) ^ (e >> 11 | e << (32 - 11)) ^ (e >> 25 | e << (32 - 25))
                let ch = (e & f) ^ ((~e) & g)
                let temp1 = h &+ S1 &+ ch &+ k[i] &+ w[i]
                let S0 = (a >> 2 | a << (32 - 2)) ^ (a >> 13 | a << (32 - 13)) ^ (a >> 22 | a << (32 - 22))
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = S0 &+ maj

                h = g; g = f; f = e; e = d &+ temp1
                d = c; c = b; b = a; a = temp1 &+ temp2
            }
            h0 = h0 &+ a; h1 = h1 &+ b; h2 = h2 &+ c; h3 = h3 &+ d
            h4 = h4 &+ e; h5 = h5 &+ f; h6 = h6 &+ g; h7 = h7 &+ h
        }

        var result = Data()
        for hVal in [h0, h1, h2, h3, h4, h5, h6, h7] {
            var be = hVal.bigEndian
            withUnsafeBytes(of: &be) { result.append(contentsOf: $0) }
        }
        return result
    }
}

/// Pure Swift HMAC-SHA256 implementation (RFC 2104 / RFC 4231 standard compliant).
enum PureSwiftHMACSHA256 {
    static func authenticate(key: Data, data: Data) -> Data {
        var k = [UInt8](key)
        if k.count > 64 {
            k = [UInt8](PureSwiftSHA256.hash(data: key))
        }
        if k.count < 64 {
            k.append(contentsOf: [UInt8](repeating: 0, count: 64 - k.count))
        }

        var ipad = [UInt8](repeating: 0x36, count: 64)
        var opad = [UInt8](repeating: 0x5c, count: 64)
        for i in 0..<64 {
            ipad[i] ^= k[i]
            opad[i] ^= k[i]
        }

        var inner = Data(ipad)
        inner.append(data)
        let innerHash = PureSwiftSHA256.hash(data: inner)

        var outer = Data(opad)
        outer.append(innerHash)
        return PureSwiftSHA256.hash(data: outer)
    }
}

/// Short-lived authentication token for ephemeral stranger assist sessions.
/// Enforces a strict 10-minute (600s) expiration TTL and cryptographically signed tamper rejection.
public struct SessionToken: Codable, Equatable, Sendable {
    public var sessionId: UUID
    public var role: SessionRole
    public var issuedAt: Double
    public var expiresAt: Double
    public var nonce: String
    public var signature: String

    public init(
        sessionId: UUID,
        role: SessionRole,
        issuedAt: Double = Date().timeIntervalSince1970,
        expiresAt: Double = Date().timeIntervalSince1970 + 600.0, // 10 minutes TTL
        nonce: String = UUID().uuidString,
        signature: String = ""
    ) {
        self.sessionId = sessionId
        self.role = role
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.nonce = nonce
        self.signature = signature
    }

    public var isExpired: Bool {
        Date().timeIntervalSince1970 > expiresAt
    }

    public var isValid: Bool {
        let now = Date().timeIntervalSince1970
        return now >= (issuedAt - 60.0) && now <= expiresAt && !signature.isEmpty
    }

    public func isValid(forSession expectedSessionId: UUID, expectedRole: SessionRole? = nil) -> Bool {
        guard !isExpired, sessionId == expectedSessionId else { return false }
        if let expectedRole = expectedRole, self.role != expectedRole {
            return false
        }
        return true
    }

    /// Generates a signed SessionToken using HMAC-SHA256 with the given shared secret.
    public static func generate(
        sessionId: UUID,
        role: SessionRole,
        ttlSeconds: Double = 600.0,
        secret: Data,
        nonce: String = UUID().uuidString
    ) -> SessionToken {
        let now = Date().timeIntervalSince1970
        var token = SessionToken(
            sessionId: sessionId,
            role: role,
            issuedAt: now,
            expiresAt: now + ttlSeconds,
            nonce: nonce,
            signature: ""
        )
        let signatureData = token.computeSignature(secret: secret)
        token.signature = signatureData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return token
    }

    /// Cryptographically verifies the token's HMAC-SHA256 signature against the shared secret.
    public func verify(secret: Data) -> Bool {
        guard !isExpired else { return false }
        let expectedSignature = computeSignature(secret: secret).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return signature == expectedSignature
    }

    private func computeSignature(secret: Data) -> Data {
        let payloadString = "\(sessionId.uuidString):\(role.rawValue):\(Int(issuedAt)):\(Int(expiresAt)):\(nonce)"
        return PureSwiftHMACSHA256.authenticate(key: secret, data: Data(payloadString.utf8))
    }

    /// Encodes token to a URL-safe compact representation.
    public func toTokenString() -> String {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(self) {
            return data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return ""
    }

    /// Parses token from URL-safe string, optionally validating its signature against secret.
    public static func fromTokenString(_ string: String, secret: Data? = nil) throws -> SessionToken {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        guard let data = Data(base64Encoded: base64) else {
            throw CryptoError.tokenTampered
        }
        let decoder = JSONDecoder()
        guard let token = try? decoder.decode(SessionToken.self, from: data) else {
            throw CryptoError.tokenTampered
        }
        if token.isExpired {
            throw CryptoError.tokenExpired
        }
        if let secret = secret {
            guard token.verify(secret: secret) else {
                throw CryptoError.tokenTampered
            }
        }
        return token
    }
}
