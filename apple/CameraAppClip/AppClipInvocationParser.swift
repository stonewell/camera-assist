import Foundation
import SyncKit

/// Specific errors thrown during App Clip Universal Link or QR invocation parsing.
public enum AppClipInvocationError: Error, LocalizedError, Equatable, Sendable {
    case invalidURL
    case missingSessionId
    case invalidSessionId
    case missingToken
    case invalidToken(String)
    case tokenExpired
    case missingFragmentKey
    case invalidFragmentKey(String)
    case unsupportedUserActivity(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的 App Clip 启动链接"
        case .missingSessionId:
            return "缺少会话标识符 (s)"
        case .invalidSessionId:
            return "会话标识符格式错误"
        case .missingToken:
            return "缺少鉴权口令 (t)"
        case .invalidToken(let reason):
            return "鉴权口令无效: \(reason)"
        case .tokenExpired:
            return "帮拍会话已过期 (10分钟限制)"
        case .missingFragmentKey:
            return "缺少端到端加密密钥 (#k=...)"
        case .invalidFragmentKey(let reason):
            return "端到端密钥解析失败: \(reason)"
        case .unsupportedUserActivity(let activityType):
            return "不支持的 UserActivity 类型: \(activityType)"
        }
    }
}

/// Parsed invocation payload containing ephemeral session parameters and decoded zero-knowledge E2EE key.
public struct AppClipInvocationPayload: Sendable, Equatable {
    public let rawURL: URL
    public let sessionId: UUID
    public let tokenString: String
    public let parsedToken: SessionToken
    public let relayEndpoint: URL
    public let sessionKey: Data
    public let languageCode: String

    /// Sanitized relay URL with URL fragment stripped, safe to send over HTTP/WebSocket without leaking E2EE key.
    public var sanitizedRelayURL: URL {
        var components = URLComponents(url: relayEndpoint, resolvingAgainstBaseURL: false) ?? URLComponents()
        components.fragment = nil
        return components.url ?? relayEndpoint
    }

    public init(
        rawURL: URL,
        sessionId: UUID,
        tokenString: String,
        parsedToken: SessionToken,
        relayEndpoint: URL,
        sessionKey: Data,
        languageCode: String = "zh-Hans"
    ) {
        self.rawURL = rawURL
        self.sessionId = sessionId
        self.tokenString = tokenString
        self.parsedToken = parsedToken
        self.relayEndpoint = relayEndpoint
        self.sessionKey = sessionKey
        self.languageCode = languageCode
    }
}

/// High-performance parser extracting ephemeral session metadata and E2EE keys from App Clip invocations.
public final class AppClipInvocationParser: Sendable {
    public static let browsingWebActivityType = "NSUserActivityTypeBrowsingWeb"

    /// Parses an incoming App Clip Universal Link (`https://.../assist?s=...&t=...#k=...`).
    public static func parse(url: URL) throws -> AppClipInvocationPayload {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw AppClipInvocationError.invalidURL
        }

        // 1. Session ID (query param `s`)
        guard let sVal = components.queryItems?.first(where: { $0.name == "s" })?.value else {
            throw AppClipInvocationError.missingSessionId
        }
        guard let sessionId = UUID(uuidString: sVal) else {
            throw AppClipInvocationError.invalidSessionId
        }

        // 2. Short-lived Token (query param `t`)
        guard let tokenString = components.queryItems?.first(where: { $0.name == "t" })?.value, !tokenString.isEmpty else {
            throw AppClipInvocationError.missingToken
        }

        let parsedToken: SessionToken
        do {
            parsedToken = try SessionToken.fromTokenString(tokenString)
        } catch {
            throw AppClipInvocationError.invalidToken("\(error)")
        }

        if parsedToken.isExpired {
            throw AppClipInvocationError.tokenExpired
        }

        // 3. E2EE 256-bit Key from URL fragment (`#k=...`)
        guard let fragment = components.fragment, !fragment.isEmpty else {
            throw AppClipInvocationError.missingFragmentKey
        }

        let sessionKey: Data
        do {
            sessionKey = try URLFragmentKey.decodeKeyFromFragment(fragment)
        } catch {
            throw AppClipInvocationError.invalidFragmentKey("\(error)")
        }

        guard sessionKey.count == 32 else {
            throw AppClipInvocationError.invalidFragmentKey("Expected 32-byte 256-bit key, got \(sessionKey.count) bytes")
        }

        // 4. Relay Endpoint (optional override in query 'r' or 'relay', otherwise sanitized base URL)
        let relayParam = components.queryItems?.first(where: { $0.name == "r" || $0.name == "relay" })?.value
        let resolvedRelayURL: URL
        if let relayParam = relayParam, let customRelay = URL(string: relayParam) {
            resolvedRelayURL = customRelay
        } else {
            var relayComponents = components
            relayComponents.fragment = nil
            resolvedRelayURL = relayComponents.url ?? url
        }

        // 5. Language code (optional query 'lang', default zh-Hans)
        let lang = components.queryItems?.first(where: { $0.name == "lang" })?.value ?? "zh-Hans"

        return AppClipInvocationPayload(
            rawURL: url,
            sessionId: sessionId,
            tokenString: tokenString,
            parsedToken: parsedToken,
            relayEndpoint: resolvedRelayURL,
            sessionKey: sessionKey,
            languageCode: lang
        )
    }

    /// Parses an incoming NSUserActivity from iOS App Clip launch.
    public static func parse(userActivity: NSUserActivity) throws -> AppClipInvocationPayload {
        let isBrowsingWeb = userActivity.activityType == browsingWebActivityType || userActivity.activityType == "NSUserActivityTypeBrowsingWeb"
        guard isBrowsingWeb else {
            throw AppClipInvocationError.unsupportedUserActivity(userActivity.activityType)
        }
        guard let url = userActivity.webpageURL else {
            throw AppClipInvocationError.invalidURL
        }
        return try parse(url: url)
    }

    /// Creates a mock demo invocation payload for standalone / SwiftUI preview testing.
    public static func makeDemoInvocation(
        sessionId: UUID = UUID(),
        baseURL: URL = URL(string: "https://clip.camera-assist.app/assist")!,
        languageCode: String = "zh-Hans"
    ) -> AppClipInvocationPayload {
        let key = URLFragmentKey.generateRandomKey()
        let token = SessionToken.generate(
            sessionId: sessionId,
            role: .guest,
            ttlSeconds: 600.0,
            secret: key
        )
        let tokenStr = token.toTokenString()
        let universalLink = URLFragmentKey.buildUniversalLink(
            baseURL: baseURL,
            sessionId: sessionId,
            token: tokenStr,
            key: key
        )

        return AppClipInvocationPayload(
            rawURL: universalLink,
            sessionId: sessionId,
            tokenString: tokenStr,
            parsedToken: token,
            relayEndpoint: baseURL,
            sessionKey: key,
            languageCode: languageCode
        )
    }
}
