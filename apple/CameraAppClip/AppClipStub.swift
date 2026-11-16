import SwiftUI
import Foundation
import SyncKit

@main
struct CameraAppClipApp: App {
    @StateObject private var coordinator = AppClipCoordinator()

    var body: some Scene {
        WindowGroup {
            AppClipContentView(coordinator: coordinator)
        }
    }
}

public struct AppClipContentView: View {
    @ObservedObject public var coordinator: AppClipCoordinator

    public init(coordinator: AppClipCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        Group {
            if coordinator.hasActiveInvocation {
                AppClipHelperView(coordinator: coordinator)
            } else {
                AppClipWaitingView(coordinator: coordinator)
            }
        }
        .onOpenURL { url in
            Task {
                await coordinator.handleInvocation(url: url)
                coordinator.startViewfinderAndMotion()
            }
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            Task {
                await coordinator.handleUserActivity(activity)
                coordinator.startViewfinderAndMotion()
            }
        }
    }
}

/// Standalone waiting screen when App Clip is launched directly without an active invocation URL.
public struct AppClipWaitingView: View {
    @ObservedObject public var coordinator: AppClipCoordinator

    public init(coordinator: AppClipCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 72, weight: .light))
                    .foregroundColor(.yellow)

                VStack(spacing: 8) {
                    Text("等待帮拍会话")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)

                    Text("请用 iPhone 靠近求助者手机 NFC 标签，或扫描求助者屏幕上的帮拍二维码以发起会话")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                if let err = coordinator.errorMessage ?? coordinator.uploadError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(err)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 24)
                }

                Spacer()
            }
            .padding()
        }
    }
}
