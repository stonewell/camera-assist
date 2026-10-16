// Apple App Clip Entry Point & Overlay Stub
// Strictly pure Swift + Apple System Frameworks. Zero UniFFI / C / Rust dependencies.

import SwiftUI
import AVFoundation
import CoreMotion
import SyncKit

@main
struct CameraAppClipApp: App {
    var body: some Scene {
        WindowGroup {
            AppClipContentView()
        }
    }
}

struct AppClipContentView: View {
    @State private var sessionState: SyncStatus = .pending
    @State private var reference: ReferencePackage? = nil
    @State private var shutterFired = false

    var body: some View {
        ZStack {
            // Camera Preview Placeholder
            Color.black.ignoresSafeArea()

            // Reference Ghost / Silhouette Overlay
            if let ref = reference {
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height

                    Rectangle()
                        .strokeBorder(Color.yellow.opacity(0.8), lineWidth: 2)
                        .frame(
                            width: CGFloat(ref.targetFraming.width) * w,
                            height: CGFloat(ref.targetFraming.height) * h
                        )
                        .position(
                            x: CGFloat(ref.targetFraming.center.x) * w,
                            y: CGFloat(ref.targetFraming.center.y) * h
                        )
                }

                // Audio / Visual prompt guidance
                VStack {
                    Text("请对齐黄色方框并保持水平")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.black.opacity(0.6).cornerRadius(8))
                        .padding(.top, 40)
                    Spacer()
                }
            }

            // Controls & Shutter
            VStack {
                Spacer()
                Button(action: {
                    shutterFired = true
                    sessionState = .captured
                }) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 72, height: 72)
                        .overlay(
                            Circle()
                                .stroke(Color.black.opacity(0.2), lineWidth: 4)
                                .frame(width: 64, height: 64)
                        )
                }
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            loadMockSession()
        }
    }

    private func loadMockSession() {
        self.reference = ReferencePackage(
            ownerDeviceToken: "owner-device-token-demo",
            promptKey: "stranger.align_ghost",
            targetFraming: NormalizedRect(x: 0.2, y: 0.15, width: 0.6, height: 0.7),
            compositionType: "center_half_body"
        )
    }
}
