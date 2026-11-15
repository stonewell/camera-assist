import Foundation
import SwiftUI

// MARK: - Notification Name Extension

extension Notification.Name {
    /// Notification broadcast when quick launch is requested via iOS 18 ControlWidget, Lock Screen, or deep link.
    public static let cameraAssistQuickLaunchRequested = Notification.Name("cameraAssistQuickLaunchRequested")
}

// MARK: - Camera Launch Mode

/// Modes in which CameraApp can be launched from external shortcuts, Lock Screen, or App Clip handoffs.
public enum CameraLaunchMode: String, CaseIterable, Sendable, Codable {
    /// Full live viewfinder with real-time pose estimation and composition guidance.
    case live = "live"

    /// Standard camera mode without augmented guidance overlays.
    case normal = "normal"

    /// Stranger helper mode triggered via session handoff or QR/NFC link.
    case stranger = "stranger"
}

// MARK: - Camera Quick Launch Request

/// Payload representing an incoming quick launch invocation.
public struct CameraQuickLaunchRequest: Sendable, Equatable {
    public let mode: CameraLaunchMode
    public let zoomPreset: String?
    public let timestamp: Date

    public init(
        mode: CameraLaunchMode = .live,
        zoomPreset: String? = nil,
        timestamp: Date = Date()
    ) {
        self.mode = mode
        self.zoomPreset = zoomPreset
        self.timestamp = timestamp
    }

    /// Deep link URL representation (e.g. `camera-assist://launch?mode=live&zoom=1x`).
    public var launchURL: URL? {
        var components = URLComponents()
        components.scheme = "camera-assist"
        components.host = "launch"
        var items: [URLQueryItem] = [
            URLQueryItem(name: "mode", value: mode.rawValue)
        ]
        if let zoom = zoomPreset {
            items.append(URLQueryItem(name: "zoom", value: zoom))
        }
        components.queryItems = items
        return components.url
    }

    /// Parses deep link URLs including `camera-assist://launch?mode=live` and `camera-assist://stranger`.
    public static func parse(url: URL) -> CameraQuickLaunchRequest? {
        guard url.scheme == "camera-assist" else { return nil }

        let host = url.host ?? ""
        var resolvedMode: CameraLaunchMode = .live
        var resolvedZoom: String? = nil

        if host == "stranger" {
            resolvedMode = .stranger
        } else if host == "normal" {
            resolvedMode = .normal
        } else if host == "live" {
            resolvedMode = .live
        }

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let items = components.queryItems {
            if let modeParam = items.first(where: { $0.name == "mode" })?.value,
               let parsed = CameraLaunchMode(rawValue: modeParam) {
                resolvedMode = parsed
            }
            if let zoomParam = items.first(where: { $0.name == "zoom" })?.value {
                resolvedZoom = zoomParam
            }
        }

        return CameraQuickLaunchRequest(
            mode: resolvedMode,
            zoomPreset: resolvedZoom,
            timestamp: Date()
        )
    }
}

// MARK: - Control Widget Descriptor

/// Metadata defining the iOS 18 Control Center and Lock Screen widget entry point.
public struct CameraControlWidgetDescriptor: Sendable {
    public static let kind: String = "com.cameraassist.control.launch"
    public static let displayName: String = "帮拍相机"
    public static let description: String = "一键快速打开帮拍相机并开启智能构图指引"

    public init() {}
}

// MARK: - App Intent (iOS 18+ / macOS 15+)

#if canImport(AppIntents)
import AppIntents

/// AppIntent executed when tapping the iOS 18 Control Center or Lock Screen widget.
@available(iOS 18.0, macOS 15.0, *)
public struct OpenCameraAssistIntent: AppIntent {
    public static let title: LocalizedStringResource = "打开帮拍相机"
    public static let description = IntentDescription("快速启动帮拍相机并进入实时智能构图模式")
    public static let openAppWhenRun: Bool = true

    @Parameter(title: "启动模式", default: "live")
    public var modeString: String

    public init() {
        self.modeString = "live"
    }

    public init(mode: CameraLaunchMode) {
        self.modeString = mode.rawValue
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        let mode = CameraLaunchMode(rawValue: modeString) ?? .live
        let request = CameraQuickLaunchRequest(mode: mode, timestamp: Date())

        NotificationCenter.default.post(
            name: .cameraAssistQuickLaunchRequested,
            object: nil,
            userInfo: ["request": request]
        )

        return .result()
    }
}
#endif

// MARK: - iOS 18 ControlWidget

#if canImport(WidgetKit) && canImport(AppIntents) && os(iOS)
import WidgetKit
import AppIntents

/// iOS 18 Lock Screen and Control Center quick launch button widget.
@available(iOS 18.0, *)
public struct CameraAssistControlWidget: ControlWidget {
    public static let kind: String = CameraControlWidgetDescriptor.kind

    public init() {}

    public var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenCameraAssistIntent(mode: .live)) {
                Label("帮拍相机", systemImage: "camera.viewfinder")
            }
        }
        .displayName("帮拍相机")
        .description("一键快速打开帮拍相机并开启智能构图指引")
    }
}
#endif
