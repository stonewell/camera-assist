import SwiftUI
import CaptureKit
import PerceptionKit
import ComposeKit
import SyncKit

#if canImport(UIKit)
import UIKit
#endif

@main
struct CameraApp: App {
    @StateObject private var coordinator = CameraCoordinator()

    var body: some Scene {
        WindowGroup {
            CameraViewfinderScreen(coordinator: coordinator)
        }
    }
}

/// 3x3 Rule-of-Thirds grid overlay for viewfinder composition assistance.
public struct RuleOfThirdsGridView: View {
    public init() {}

    public var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            Path { path in
                // Vertical lines at 1/3 and 2/3
                path.move(to: CGPoint(x: w / 3.0, y: 0))
                path.addLine(to: CGPoint(x: w / 3.0, y: h))
                path.move(to: CGPoint(x: 2.0 * w / 3.0, y: 0))
                path.addLine(to: CGPoint(x: 2.0 * w / 3.0, y: h))

                // Horizontal lines at 1/3 and 2/3
                path.move(to: CGPoint(x: 0, y: h / 3.0))
                path.addLine(to: CGPoint(x: w, y: h / 3.0))
                path.move(to: CGPoint(x: 0, y: 2.0 * h / 3.0))
                path.addLine(to: CGPoint(x: w, y: 2.0 * h / 3.0))
            }
            .stroke(Color.white.opacity(0.35), lineWidth: 1.0)
        }
        .allowsHitTesting(false)
    }
}

/// Sheet displaying preview of the latest captured photo or camera roll image.
public struct PhotoThumbnailPreviewSheet: View {
    @ObservedObject public var coordinator: CameraCoordinator
    @Environment(\.dismiss) private var dismiss

    public init(coordinator: CameraCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("最新照片")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    Spacer()

                    Button(action: {
                        coordinator.isThumbnailPreviewPresented = false
                        dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

                Divider()
                    .background(Color.white.opacity(0.15))

                Spacer()

                #if canImport(UIKit)
                if let data = coordinator.latestThumbnailData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding()
                } else {
                    emptyStateView
                }
                #else
                emptyStateView
                #endif

                Spacer()
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.4))
            Text("暂无最近拍摄的照片")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))
        }
    }
}

/// Full-featured iOS Camera Assistant Viewfinder screen unifying
/// live AVFoundation preview, real-time skeletal pose & telemetry HUD,
/// 24MP shutter capture button, zoom lens presets, and Stranger Assist flow.
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

                // 2. 3x3 Rule-of-Thirds Grid Overlay (TASK-18)
                if coordinator.isGridVisible {
                    RuleOfThirdsGridView()
                        .allowsHitTesting(false)
                        .ignoresSafeArea()
                }

                // 3. Interactive User Guidance HUD (Target lines, horizon indicator, good-to-shoot pulse, active hint pill)
                UserGuidanceHUD(
                    isEnabled: $coordinator.isUserGuidanceEnabled,
                    output: coordinator.latestComposeOutput,
                    hint: coordinator.activeHint,
                    rollDeg: coordinator.telemetry.rollDeg,
                    pitchDeg: coordinator.telemetry.pitchDeg,
                    boundingBox: coordinator.primaryBoundingBox,
                    subjectBoxes: coordinator.subjectBoxes,
                    isFlatish: coordinator.isFlatish,
                    isEngineDegraded: coordinator.isEngineDegraded,
                    onSelectZoom: { factor in
                        Task {
                            await coordinator.applyRecommendedZoom(factor: factor)
                        }
                    }
                )

                // 4. Perception Debug HUD Overlay (Pose skeleton, Horizon level, Bounding box, Telemetry)
                PerceptionDebugHUD(
                    isVisible: $coordinator.isDebugHUDVisible,
                    telemetry: coordinator.telemetry,
                    joints: coordinator.renderJoints,
                    boundingBox: coordinator.primaryBoundingBox
                )

                // 5. Non-blocking floating active banner toast (TASK-14)
                if let banner = coordinator.activeBanner {
                    VStack {
                        bannerToastView(banner)
                            .padding(.top, 48)
                            .padding(.horizontal, 16)
                            .transition(.move(edge: .top).combined(with: .opacity))

                        Spacer()
                    }
                    .zIndex(100)
                }

                // 6. User Viewfinder Controls & Overlays
                VStack(spacing: 0) {
                    // Top Navigation Bar
                    topNavigationBar
                        .padding(.top, 44)
                        .padding(.horizontal, 16)

                    // Dynamic Composition Hint Banner
                    hintBanner
                        .padding(.top, 12)

                    Spacer()

                    // Exposure Bias (EV) Slider
                    if coordinator.isEVSliderVisible {
                        evSliderBar
                            .padding(.bottom, 12)
                    }

                    // Bottom Control Deck (Zoom Presets + Shutter Button)
                    bottomControlBar
                        .padding(.bottom, 36)
                        .padding(.horizontal, 24)
                }

                // 7. Large Countdown Overlay + tap-to-cancel (TASK-18)
                if let count = coordinator.countdownRemaining {
                    ZStack {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                            .onTapGesture {
                                coordinator.cancelCountdown()
                            }

                        VStack(spacing: 16) {
                            Text("\(count)")
                                .font(.system(size: 104, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.8), radius: 10, x: 0, y: 4)

                            Button(action: {
                                coordinator.cancelCountdown()
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 14, weight: .bold))
                                    Text("取消倒计时")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                }
                                .foregroundColor(.white.opacity(0.9))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.65))
                                .clipShape(Capsule())
                            }
                        }
                    }
                    .zIndex(150)
                    .transition(.opacity)
                }

                // 8. Camera permission denied/restricted full-screen guidance overlay (TASK-14)
                if coordinator.cameraPermissionStatus == .denied || coordinator.cameraPermissionStatus == .restricted {
                    cameraPermissionOverlay
                        .zIndex(200)
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
        .onOpenURL { url in
            _ = coordinator.handleDeepLink(url)
        }
        .sheet(isPresented: $coordinator.isStrangerAssistPresented) {
            StrangerAssistQRSheet(coordinator: coordinator)
        }
        .sheet(isPresented: $coordinator.isThumbnailPreviewPresented) {
            PhotoThumbnailPreviewSheet(coordinator: coordinator)
        }
        #if os(iOS) || os(tvOS) || os(watchOS)
        .fullScreenCover(isPresented: $coordinator.isStrangerReviewPresented) {
            StrangerCaptureReviewView(coordinator: coordinator)
        }
        #else
        .sheet(isPresented: $coordinator.isStrangerReviewPresented) {
            StrangerCaptureReviewView(coordinator: coordinator)
        }
        #endif
    }

    // MARK: - Top Navigation Bar

    private var topNavigationBar: some View {
        HStack(spacing: 8) {
            Text("帮拍相机")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.white)

            Spacer(minLength: 4)

            // Flash mode toggle (Auto / On / Off)
            Button(action: { coordinator.cycleFlashMode() }) {
                Image(systemName: flashIconName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(coordinator.flashMode == .off ? .white.opacity(0.5) : .yellow)
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }

            // Self-Timer toggle (0s / 3s / 10s)
            Button(action: { coordinator.cycleTimerDuration() }) {
                HStack(spacing: 1) {
                    Image(systemName: "timer")
                        .font(.system(size: 11, weight: .bold))
                    if coordinator.timerDuration != .off {
                        Text("\(coordinator.timerDuration.rawValue)s")
                            .font(.system(size: 8, weight: .heavy))
                    }
                }
                .foregroundColor(coordinator.timerDuration == .off ? .white.opacity(0.5) : .yellow)
                .frame(width: 32, height: 32)
                .background(Color.black.opacity(0.6))
                .clipShape(Circle())
            }

            // 3x3 Grid toggle
            Button(action: { coordinator.toggleGrid() }) {
                Image(systemName: "grid")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(coordinator.isGridVisible ? .yellow : .white.opacity(0.5))
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }

            // EV slider toggle
            Button(action: { coordinator.toggleEVSlider() }) {
                Image(systemName: coordinator.isEVSliderVisible ? "plusminus.circle.fill" : "plusminus.circle")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(coordinator.isEVSliderVisible ? .yellow : .white.opacity(0.5))
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }

            // Voice prompter mute toggle
            Button(action: { coordinator.toggleVoice() }) {
                Image(systemName: coordinator.isVoiceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(coordinator.isVoiceEnabled ? .yellow : .white.opacity(0.5))
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }

            // Guidance HUD toggle
            Button(action: { coordinator.isUserGuidanceEnabled.toggle() }) {
                Image(systemName: coordinator.isUserGuidanceEnabled ? "sparkles" : "sparkles.rectangle.stack")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(coordinator.isUserGuidanceEnabled ? .yellow : .white.opacity(0.5))
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }

            // Stranger Assist entry button (TASK-15)
            Button(action: { coordinator.openStrangerAssist() }) {
                HStack(spacing: 3) {
                    Image(systemName: "person.2.badge.gearshape.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("帮拍")
                        .font(.caption2)
                        .fontWeight(.bold)
                }
                .foregroundColor(.yellow)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.6))
                .clipShape(Capsule())
            }

            // 24MP computational imaging badge
            HStack(spacing: 3) {
                Circle()
                    .fill(Color.yellow)
                    .frame(width: 5, height: 5)
                Text("24MP")
                    .font(.caption2)
                    .fontWeight(.black)
                    .foregroundColor(.yellow)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.6))
            .clipShape(Capsule())
        }
    }

    private var flashIconName: String {
        switch coordinator.flashMode {
        case .auto:
            return "bolt.badge.a.fill"
        case .on:
            return "bolt.fill"
        case .off:
            return "bolt.slash.fill"
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

    // MARK: - Exposure Compensation (EV) Slider Bar

    private var evSliderBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "sun.min")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.7))

            Text("-2.0")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))

            Slider(
                value: Binding(
                    get: { coordinator.exposureBias },
                    set: { coordinator.setExposureBias($0) }
                ),
                in: -2.0...2.0,
                step: 0.1
            )
            .accentColor(.yellow)

            Text("+2.0")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))

            Image(systemName: "sun.max.fill")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.7))

            Text(String(format: "%+.1f EV", coordinator.exposureBias))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.yellow)
                .frame(width: 58, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.75))
        .clipShape(Capsule())
        .padding(.horizontal, 24)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
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

            // 24MP Capture Shutter Row with Thumbnail Button
            HStack {
                // Bottom-left Photo Thumbnail Button
                Button(action: {
                    coordinator.isThumbnailPreviewPresented = true
                }) {
                    thumbnailPreviewButton
                }
                .frame(width: 60, height: 60)

                Spacer()

                // Shutter Button
                Button(action: {
                    coordinator.triggerShutter()
                }) {
                    ZStack {
                        Circle()
                            .stroke(Color.white, lineWidth: 4)
                            .frame(width: 76, height: 76)
                        Circle()
                            .fill(coordinator.isCapturing ? Color.gray : (coordinator.countdownRemaining != nil ? Color.orange : Color.white))
                            .frame(width: 64, height: 64)
                        if let count = coordinator.countdownRemaining {
                            Text("\(count)")
                                .font(.system(size: 24, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                        }
                    }
                }
                .disabled(coordinator.isCapturing)

                Spacer()

                // Symmetrical placeholder
                Color.clear
                    .frame(width: 60, height: 60)
            }
        }
    }

    private var thumbnailPreviewButton: some View {
        Group {
            #if canImport(UIKit)
            if let data = coordinator.latestThumbnailData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.85), lineWidth: 2)
                    )
                    .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
            } else {
                defaultThumbnailPlaceholder
            }
            #else
            defaultThumbnailPlaceholder
            #endif
        }
    }

    private var defaultThumbnailPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.6))
                .frame(width: 48, height: 48)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.6), lineWidth: 1.5)
                )
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 20))
                .foregroundColor(.white.opacity(0.8))
        }
    }

    // MARK: - Banner Toast View (TASK-14)

    private func bannerToastView(_ banner: CameraBannerMessage) -> some View {
        let (iconName, tintColor) = bannerSeverityStyle(banner.severity)
        return HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(tintColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(banner.title)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Text(banner.message)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
            }

            Spacer()

            if let actionTitle = banner.actionTitle, let actionType = banner.actionType {
                Button(action: {
                    coordinator.handleBannerAction(actionType)
                }) {
                    Text(actionTitle)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.yellow)
                        .clipShape(Capsule())
                }
            }

            Button(action: {
                coordinator.dismissBanner()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(tintColor.opacity(0.5), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 6, x: 0, y: 3)
    }

    private func bannerSeverityStyle(_ severity: CameraBannerSeverity) -> (String, Color) {
        switch severity {
        case .info:
            return ("info.circle.fill", .blue)
        case .warning:
            return ("exclamationmark.triangle.fill", .yellow)
        case .critical:
            return ("xmark.octagon.fill", .red)
        }
    }

    // MARK: - Camera Permission Guidance Overlay (TASK-14)

    private var cameraPermissionOverlay: some View {
        ZStack {
            Color.black.opacity(0.96).ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 54))
                    .foregroundColor(.yellow)

                Text("需要相机权限")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text("帮拍相机需要访问您的设备相机，以提供实时构图智能辅助并拍摄 24MP 高质量照片。请在系统设置中启用相机访问。")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button(action: {
                    #if canImport(UIKit)
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                    #endif
                }) {
                    Text("打开系统设置")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(Color.yellow)
                        .clipShape(Capsule())
                }
                .padding(.top, 8)
            }
        }
    }
}
