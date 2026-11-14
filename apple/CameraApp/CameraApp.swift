import SwiftUI
import CaptureKit
import PerceptionKit
import ComposeKit
import SyncKit

@main
struct CameraApp: App {
    @StateObject private var coordinator = CameraCoordinator()

    var body: some Scene {
        WindowGroup {
            CameraViewfinderScreen(coordinator: coordinator)
        }
    }
}

/// Full-featured iOS Camera Assistant Viewfinder screen unifying
/// live AVFoundation preview, real-time skeletal pose & telemetry HUD,
/// 24MP shutter capture button, and zoom lens presets.
public struct CameraViewfinderScreen: View {
    @ObservedObject public var coordinator: CameraCoordinator

    public init(coordinator: CameraCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        GeometryReader { _ in
            ZStack {
                Color.black.ignoresSafeArea()

                // 1. Camera Viewfinder Video Preview
                CameraPreviewView(
                    sessionManager: coordinator.sessionManager,
                    isSessionRunning: coordinator.isSessionRunning
                )
                .ignoresSafeArea()

                // 2. Perception Debug HUD Overlay (Pose skeleton, Horizon level, Bounding box, Telemetry)
                PerceptionDebugHUD(
                    isVisible: $coordinator.isDebugHUDVisible,
                    telemetry: coordinator.telemetry,
                    joints: coordinator.renderJoints,
                    boundingBox: coordinator.primaryBoundingBox
                )

                // 3. User Viewfinder Controls & Overlays
                VStack(spacing: 0) {
                    // Top Navigation Bar
                    topNavigationBar
                        .padding(.top, 44)
                        .padding(.horizontal, 20)

                    // Dynamic Composition Hint Banner
                    hintBanner
                        .padding(.top, 12)

                    Spacer()

                    // Bottom Control Deck (Zoom Presets + Shutter Button)
                    bottomControlBar
                        .padding(.bottom, 36)
                        .padding(.horizontal, 24)
                }
            }
        }
        .task {
            await coordinator.start()
        }
        .onDisappear {
            Task {
                await coordinator.stop()
            }
        }
    }

    // MARK: - Top Navigation Bar

    private var topNavigationBar: some View {
        HStack {
            Text("帮拍相机")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.white)

            Spacer()

            // 24MP computational imaging badge
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.yellow)
                    .frame(width: 6, height: 6)
                Text("24MP")
                    .font(.caption2)
                    .fontWeight(.black)
                    .foregroundColor(.yellow)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.6))
            .clipShape(Capsule())
        }
    }

    // MARK: - Dynamic Hint Banner

    private var hintBanner: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(coordinator.isGoodToShoot ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(coordinator.activeHintBannerText)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.65))
        .clipShape(Capsule())
        .animation(.easeInOut(duration: 0.2), value: coordinator.activeHintBannerText)
    }

    // MARK: - Bottom Control Deck

    private var bottomControlBar: some View {
        VStack(spacing: 20) {
            // Optical/Digital Zoom Lens Selector (0.5x, 1x, 2x, 3x)
            HStack(spacing: 16) {
                ForEach(CameraZoomPreset.allCases) { preset in
                    Button(action: {
                        Task {
                            await coordinator.selectZoomPreset(preset)
                        }
                    }) {
                        Text(preset.title)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(coordinator.currentZoomPreset == preset ? .yellow : .white)
                            .frame(width: 44, height: 44)
                            .background(
                                coordinator.currentZoomPreset == preset
                                    ? Color.black.opacity(0.8)
                                    : Color.black.opacity(0.4)
                            )
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(
                                        coordinator.currentZoomPreset == preset ? Color.yellow : Color.clear,
                                        lineWidth: 2
                                    )
                            )
                    }
                }
            }

            // 24MP Capture Shutter Button
            HStack {
                Spacer()

                Button(action: {
                    Task {
                        _ = await coordinator.capturePhoto()
                    }
                }) {
                    ZStack {
                        Circle()
                            .stroke(Color.white, lineWidth: 4)
                            .frame(width: 76, height: 76)
                        Circle()
                            .fill(coordinator.isCapturing ? Color.gray : Color.white)
                            .frame(width: 64, height: 64)
                    }
                }
                .disabled(coordinator.isCapturing)

                Spacer()
            }
        }
    }
}
