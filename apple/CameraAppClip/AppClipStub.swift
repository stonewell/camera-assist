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
        AppClipHelperView(coordinator: coordinator)
            .onOpenURL { url in
                Task {
                    await coordinator.handleInvocation(url: url)
                }
            }
            .onContinueUserActivity(AppClipInvocationParser.browsingWebActivityType) { activity in
                Task {
                    await coordinator.handleUserActivity(activity)
                }
            }
            .task {
                if !coordinator.hasActiveInvocation && coordinator.syncStatus == .pending && coordinator.invocationPayload == nil {
                    await coordinator.startStandaloneDemoSession()
                }
                coordinator.startViewfinderAndMotion()
            }
    }
}
