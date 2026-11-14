import SwiftUI
import CoreGraphics

#if canImport(AVFoundation)
import AVFoundation
#endif

#if canImport(UIKit)
import UIKit
#endif

import SyncKit

// MARK: - Camera Preview Layer View

#if canImport(UIKit) && canImport(AVFoundation)
public struct AppClipCameraPreviewLayerView: UIViewRepresentable {
    public let session: AVCaptureSession

    public init(session: AVCaptureSession) {
        self.session = session
    }

    public func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    public func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    public final class PreviewUIView: UIView {
        override public class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }
        public var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
#else
public struct AppClipCameraPreviewLayerView: View {
    public init() {}
    public var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [Color.black, Color(white: 0.12), Color.black]),
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}
#endif

// MARK: - Ghost Silhouette Overlay View

/// Overlays the target silhouette / reference photo outline with adjustable opacity.
public struct GhostSilhouetteOverlayView: View {
    public let reference: ReferencePackage
    public let opacity: Double

    public init(reference: ReferencePackage, opacity: Double = 0.5) {
        self.reference = reference
        self.opacity = opacity
    }

    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let box = reference.targetFraming
            let rect = CGRect(
                x: CGFloat(box.x) * w,
                y: CGFloat(box.y) * h,
                width: CGFloat(box.width) * w,
                height: CGFloat(box.height) * h
            )

            ZStack {
                #if canImport(UIKit)
                if let data = reference.thumbnailJpegData ?? reference.previewThumbnailData,
                   let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: rect.width, height: rect.height)
                        .clipped()
                        .opacity(opacity)
                        .position(x: rect.midX, y: rect.midY)
                }
                #endif

                // Faint yellow reference contour
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        Color.yellow.opacity(max(0.3, opacity)),
                        style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                    )
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Target Alignment Overlay View

/// Interactive viewfinder target box, horizon level line, and stranger instruction banner.
public struct TargetAlignmentOverlayView: View {
    public let alignment: StrangerAlignmentState
    public let reference: ReferencePackage

    public init(alignment: StrangerAlignmentState, reference: ReferencePackage) {
        self.alignment = alignment
        self.reference = reference
    }

    private var targetColor: Color {
        if alignment.isReadyToShoot {
            return .green
        } else if alignment.isRollAligned || alignment.isPitchAligned {
            return .yellow
        } else {
            return .red
        }
    }

    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let box = reference.targetFraming
            let rect = CGRect(
                x: CGFloat(box.x) * w,
                y: CGFloat(box.y) * h,
                width: CGFloat(box.width) * w,
                height: CGFloat(box.height) * h
            )
            let center = CGPoint(x: w / 2.0, y: h / 2.0)

            ZStack {
                // 1. Dynamic framing target box
                RoundedRectangle(cornerRadius: 14)
                    .stroke(targetColor, lineWidth: alignment.isReadyToShoot ? 3.0 : 2.0)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .animation(.easeOut(duration: 0.15), value: alignment.isReadyToShoot)

                // 2. Horizon Level Line & Notches
                HStack {
                    Rectangle()
                        .fill(Color.white.opacity(0.4))
                        .frame(width: 22, height: 2)
                    Spacer()
                    Rectangle()
                        .fill(Color.white.opacity(0.4))
                        .frame(width: 22, height: 2)
                }
                .frame(width: w * 0.52)
                .position(center)

                Rectangle()
                    .fill(alignment.isRollAligned ? Color.green : Color.yellow)
                    .frame(width: w * 0.32, height: alignment.isRollAligned ? 2.5 : 2)
                    .rotationEffect(.degrees(alignment.rollDeg))
                    .position(center)
                    .animation(.easeOut(duration: 0.1), value: alignment.rollDeg)

                // 3. Top Instruction Banner (Chinese primary + English subtitle)
                VStack(spacing: 3) {
                    Text(alignment.activeCue.primary)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)

                    if !alignment.activeCue.subtitle.isEmpty {
                        Text(alignment.activeCue.subtitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.75))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(targetColor.opacity(0.7), lineWidth: 1.5)
                )
                .position(x: w / 2.0, y: 70)
                .animation(.easeInOut(duration: 0.2), value: alignment.activeCue.primary)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - App Clip Completion View

/// Zero-registration completion screen confirming end-to-end encrypted photo upload.
public struct AppClipCompletionView: View {
    public let isSessionFinished: Bool
    public let onTakeAnother: () -> Void
    public let onFinishAndCleanUp: () -> Void

    public init(
        isSessionFinished: Bool = false,
        onTakeAnother: @escaping () -> Void,
        onFinishAndCleanUp: @escaping () -> Void
    ) {
        self.isSessionFinished = isSessionFinished
        self.onTakeAnother = onTakeAnother
        self.onFinishAndCleanUp = onFinishAndCleanUp
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundColor(.green)

                Text("帮拍完成！")
                    .font(.system(size: 26, weight: .black))
                    .foregroundColor(.white)

                Text(isSessionFinished ? "会话已结束，可关闭此页面" : "照片已端到端加密传回失主手机")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                    Text("Curve25519 + AES-GCM 端到端加密 • 本机不留存任何照片")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.1))
                .clipShape(Capsule())

                Spacer()

                VStack(spacing: 12) {
                    if !isSessionFinished {
                        Button(action: onTakeAnother) {
                            Text("再拍一张")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.white)
                                .clipShape(Capsule())
                        }

                        Button(action: onFinishAndCleanUp) {
                            Text("完成并清理")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                    } else {
                        Text("会话已结束，可关闭此页面")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.vertical, 12)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 36)
            }
        }
    }
}

// MARK: - App Clip Helper View (Main Container)

/// Unified App Clip helper screen providing the zero-install stranger camera assist experience.
public struct AppClipHelperView: View {
    @ObservedObject public var coordinator: AppClipCoordinator

    public init(coordinator: AppClipCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // 1. Camera Viewfinder Layer
            #if canImport(AVFoundation)
            AppClipCameraPreviewLayerView(session: coordinator.captureSession)
                .ignoresSafeArea()
            #else
            AppClipCameraPreviewLayerView()
                .ignoresSafeArea()
            #endif

            // 2. Ghost Reference Overlay
            if let ref = coordinator.referencePackage {
                GhostSilhouetteOverlayView(reference: ref, opacity: coordinator.ghostOpacity)
                    .ignoresSafeArea()

                // 3. Target Alignment Overlay
                TargetAlignmentOverlayView(alignment: coordinator.alignmentState, reference: ref)
                    .ignoresSafeArea()
            }

            // 4. Viewfinder Bottom Deck
            VStack {
                Spacer()

                // Opacity slider bar
                HStack(spacing: 12) {
                    Image(systemName: "person.fill.viewfinder")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.yellow)

                    Slider(value: $coordinator.ghostOpacity, in: 0.1...0.9)
                        .accentColor(.yellow)

                    Text(String(format: "%.0f%%", coordinator.ghostOpacity * 100))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(width: 36)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.55))
                .clipShape(Capsule())
                .padding(.horizontal, 40)
                .padding(.bottom, 16)

                // Shutter Button
                Button(action: {
                    Task {
                        await coordinator.captureAndUploadPhoto()
                    }
                }) {
                    ZStack {
                        Circle()
                            .stroke(
                                coordinator.alignmentState.isReadyToShoot ? Color.green : Color.white.opacity(0.4),
                                lineWidth: coordinator.alignmentState.isReadyToShoot ? 4 : 2
                            )
                            .frame(width: 76, height: 76)
                            .scaleEffect(coordinator.alignmentState.isReadyToShoot ? 1.05 : 1.0)
                            .animation(
                                coordinator.alignmentState.isReadyToShoot ? .easeInOut(duration: 0.4).repeatForever(autoreverses: true) : .default,
                                value: coordinator.alignmentState.isReadyToShoot
                            )

                        Circle()
                            .fill(Color.white)
                            .frame(width: 64, height: 64)
                    }
                }
                .disabled(coordinator.isCapturing || coordinator.isUploading || coordinator.isSessionFinished)
                .padding(.bottom, 32)
            }

            // 5. Uploading Indicator
            if coordinator.isUploading {
                ZStack {
                    Color.black.opacity(0.6).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                        Text("正在加密传回照片...")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }

            // 6. Completion Screen
            if coordinator.isCompleted {
                AppClipCompletionView(
                    isSessionFinished: coordinator.isSessionFinished,
                    onTakeAnother: {
                        coordinator.prepareForAnotherShot()
                    },
                    onFinishAndCleanUp: {
                        coordinator.finishAndPurgeCache()
                    }
                )
            }
        }
    }
}
