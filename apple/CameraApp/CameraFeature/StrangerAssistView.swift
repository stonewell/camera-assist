import Foundation
import SwiftUI
import CoreGraphics
import SyncKit

#if canImport(UIKit)
import UIKit
#endif

#if canImport(CoreImage)
import CoreImage
#if canImport(CoreImage.CIFilterBuiltins)
import CoreImage.CIFilterBuiltins
#endif
#endif

// MARK: - QR Code Helper

#if canImport(CoreImage)
private let sharedQRContext = CIContext()
#endif

private func generateQRCode(from string: String) -> CGImage? {
    guard !string.isEmpty else { return nil }
    #if canImport(CoreImage)
    let data = Data(string.utf8)
    guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
    filter.setValue(data, forKey: "inputMessage")
    filter.setValue("M", forKey: "inputCorrectionLevel")
    guard let outputImage = filter.outputImage else { return nil }
    let transform = CGAffineTransform(scaleX: 10, y: 10)
    let scaled = outputImage.transformed(by: transform)
    return sharedQRContext.createCGImage(scaled, from: scaled.extent)
    #else
    return nil
    #endif
}

// MARK: - Stranger Assist QR Sheet

/// Sheet displayed to the photo owner showing the ephemeral Universal Link QR code,
/// 6-character short code, 10-minute session countdown, sync status, and launch controls.
public struct StrangerAssistQRSheet: View {
    @ObservedObject public var coordinator: CameraCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var qrImage: CGImage? = nil

    public init(coordinator: CameraCoordinator) {
        self.coordinator = coordinator
        let initialImage = coordinator.strangerUniversalLink.flatMap { generateQRCode(from: $0.absoluteString) }
        self._qrImage = State(initialValue: initialImage)
    }

    private var formattedTime: String {
        let seconds = max(0, coordinator.strangerSessionRemainingSeconds)
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    private var statusTitle: String {
        switch coordinator.strangerSyncStatus {
        case .pending:
            return "等待连接"
        case .connecting:
            return "正在连接..."
        case .ready:
            return "帮拍就绪"
        case .syncing:
            return "正在同步参考构图..."
        case .captured:
            return "已收到帮拍照片"
        case .completed:
            return "帮拍完成"
        case .expired:
            return "口令已过期"
        case .failed:
            return "连接异常"
        }
    }

    private var statusColor: Color {
        switch coordinator.strangerSyncStatus {
        case .pending:
            return .yellow
        case .connecting, .syncing:
            return .blue
        case .ready, .completed, .captured:
            return .green
        case .expired, .failed:
            return .red
        }
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()

            VStack(spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("路人帮拍")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        Text("让朋友或路人扫码帮你拍出理想构图")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    Spacer()
                    Button(action: {
                        coordinator.isStrangerAssistPresented = false
                        dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)

                // Sync Status Badge
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(statusTitle)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(statusColor)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.5))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(statusColor.opacity(0.4), lineWidth: 1))

                // QR Code Card
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white)
                        .frame(width: 240, height: 240)
                        .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)

                    if let cgImage = qrImage {
                        #if canImport(UIKit)
                        Image(uiImage: UIImage(cgImage: cgImage))
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 200, height: 200)
                        #else
                        Image(decorative: cgImage, scale: 1.0)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 200, height: 200)
                        #endif
                    } else {
                        // Clean QR fallback view
                        VStack(spacing: 12) {
                            Image(systemName: "qrcode")
                                .font(.system(size: 64))
                                .foregroundColor(.black)
                            Text("扫码启动 App Clip")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                        }
                    }
                }

                // 6-character short code display
                VStack(spacing: 6) {
                    Text("或口头告知 6 位帮拍口令")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))

                    Text(coordinator.strangerShortCode.isEmpty ? "------" : coordinator.strangerShortCode)
                        .font(.system(size: 32, weight: .heavy, design: .monospaced))
                        .foregroundColor(.yellow)
                        .tracking(6)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.yellow.opacity(0.4), lineWidth: 1)
                        )
                }

                // 10-minute session countdown
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                    Text("口令有效期剩余：\(formattedTime)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(coordinator.strangerSessionRemainingSeconds < 60 ? .red : .white.opacity(0.8))
                }

                Spacer()

                // Actions Deck
                VStack(spacing: 12) {
                    // "发起帮拍" button: sends ReferencePackage to guest device
                    Button(action: {
                        Task {
                            await coordinator.sendStrangerReferencePackage()
                        }
                    }) {
                        HStack(spacing: 8) {
                            if coordinator.isSendingReference || coordinator.isWaitingForCapture {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .black))
                            } else {
                                Image(systemName: "arrow.up.right.circle.fill")
                                    .font(.system(size: 16, weight: .bold))
                            }
                            Text(coordinator.isWaitingForCapture ? "等待路人拍摄中..." : "发起帮拍")
                                .font(.headline)
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(coordinator.strangerSessionRemainingSeconds > 0 ? Color.yellow : Color.gray)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(coordinator.strangerSessionRemainingSeconds <= 0 || coordinator.isSendingReference || coordinator.isWaitingForCapture)

                    // "刷新口令" button: generates fresh session and link
                    Button(action: {
                        coordinator.startStrangerAssistSession()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 13, weight: .semibold))
                            Text("刷新口令")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.white.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .onAppear {
            updateQRCode(for: coordinator.strangerUniversalLink)
        }
        .onChange(of: coordinator.strangerUniversalLink) { newLink in
            updateQRCode(for: newLink)
        }
    }

    private func updateQRCode(for link: URL?) {
        guard let urlStr = link?.absoluteString else {
            qrImage = nil
            return
        }
        qrImage = generateQRCode(from: urlStr)
    }
}

// MARK: - Stranger Capture Review View

/// Full-screen review view presented once a guest photographer returns a 24MP photograph.
/// Displays returned image, angle/device telemetry comparison card, save button, and retake button.
public struct StrangerCaptureReviewView: View {
    @ObservedObject public var coordinator: CameraCoordinator
    @Environment(\.dismiss) private var dismiss

    public init(coordinator: CameraCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 16) {
                // Top bar
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("帮拍照片审核")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        Text("对方已完成拍摄并加密传回")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }

                    Spacer()

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

                    Button(action: {
                        coordinator.isStrangerReviewPresented = false
                        dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                // Photo Preview
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.black.opacity(0.8))

                    if let capture = coordinator.receivedStrangerCapture {
                        #if canImport(UIKit)
                        if let uiImage = UIImage(data: capture.fullPhotoData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        } else {
                            fallbackPreview(capture: capture)
                        }
                        #else
                        fallbackPreview(capture: capture)
                        #endif
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 48))
                                .foregroundColor(.white.opacity(0.4))
                            Text("无可用照片数据")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 16)

                // Comparison card (telemetry, angle, device)
                if let capture = coordinator.receivedStrangerCapture {
                    comparisonCard(capture: capture)
                        .padding(.horizontal, 16)
                }

                // Action Deck
                HStack(spacing: 14) {
                    // "重新帮拍" button
                    Button(action: {
                        coordinator.isStrangerReviewPresented = false
                        Task {
                            await coordinator.sendStrangerReferencePackage()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .bold))
                            Text("重新帮拍")
                                .font(.subheadline)
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.white.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    // "保存至相册" button
                    Button(action: {
                        coordinator.confirmStrangerCaptureAndSave()
                        dismiss()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.down.fill")
                                .font(.system(size: 15, weight: .bold))
                            Text("保存至相册")
                                .font(.headline)
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.yellow)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }

    private func fallbackPreview(capture: CapturePackage) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 48))
                .foregroundColor(.yellow)
            Text("24MP 照片已接收")
                .font(.headline)
                .foregroundColor(.white)
            Text(String(format: "数据大小: %.2f MB", Double(capture.fullPhotoData.count) / (1024.0 * 1024.0)))
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
        }
    }

    private func comparisonCard(capture: CapturePackage) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("拍摄设备信息与姿态")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(capture.wasReadyState ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(capture.wasReadyState ? "参考线对齐良好" : "略有偏角")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(capture.wasReadyState ? .green : .orange)
                }
            }

            HStack(spacing: 12) {
                telemetryItem(title: "机型", value: capture.deviceModel)
                Divider().frame(height: 24).background(Color.white.opacity(0.2))
                telemetryItem(title: "俯仰角", value: String(format: "%+.1f°", capture.cameraPitch))
                Divider().frame(height: 24).background(Color.white.opacity(0.2))
                telemetryItem(title: "翻滚角", value: String(format: "%+.1f°", capture.cameraRoll))
                Divider().frame(height: 24).background(Color.white.opacity(0.2))
                telemetryItem(title: "焦距", value: String(format: "%.0fmm", capture.focalLengthMm))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func telemetryItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.5))
            Text(value)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
