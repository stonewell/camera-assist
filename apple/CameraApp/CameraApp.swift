import SwiftUI
import CaptureKit
import PerceptionKit
import ComposeKit
import SyncKit

@main
struct CameraApp: App {
    @State private var isHUDVisible = true
    @State private var telemetry = DebugTelemetry()

    var body: some Scene {
        WindowGroup {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack {
                    Text("帮拍相机")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.top, 40)
                    Spacer()
                }

                PerceptionDebugHUD(
                    isVisible: $isHUDVisible,
                    telemetry: telemetry
                )
            }
        }
    }
}
