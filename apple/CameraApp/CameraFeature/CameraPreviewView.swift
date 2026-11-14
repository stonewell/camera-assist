import SwiftUI
import CaptureKit

#if canImport(UIKit) && canImport(AVFoundation)
import UIKit
import AVFoundation

/// Backing UIView holding the AVCaptureVideoPreviewLayer and handling tap-to-focus interactions.
public final class PreviewLayerContainerView: UIView {
    public override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    public var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = self.layer as? AVCaptureVideoPreviewLayer else {
            fatalError("Layer must be AVCaptureVideoPreviewLayer")
        }
        return layer
    }

    public var onTapToFocus: ((CGPoint) -> Void)?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        backgroundColor = .black
        videoPreviewLayer.videoGravity = .resizeAspectFill

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture(_:)))
        addGestureRecognizer(tapGesture)
        isUserInteractionEnabled = true
    }

    @objc private func handleTapGesture(_ recognizer: UITapGestureRecognizer) {
        let location = recognizer.location(in: self)
        let devicePoint = videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: location)
        onTapToFocus?(devicePoint)
    }
}

/// SwiftUI wrapper for the AVFoundation camera viewfinder preview stream.
public struct CameraPreviewView: UIViewRepresentable {
    public let sessionManager: CaptureSessionManager
    public let isSessionRunning: Bool

    public init(sessionManager: CaptureSessionManager, isSessionRunning: Bool = false) {
        self.sessionManager = sessionManager
        self.isSessionRunning = isSessionRunning
    }

    public func makeUIView(context: Context) -> PreviewLayerContainerView {
        let view = PreviewLayerContainerView()
        view.videoPreviewLayer.session = sessionManager.session
        view.onTapToFocus = { point in
            Task {
                await sessionManager.focusAndExpose(at: point)
            }
        }
        return view
    }

    public func updateUIView(_ uiView: PreviewLayerContainerView, context: Context) {
        if uiView.videoPreviewLayer.session !== sessionManager.session {
            uiView.videoPreviewLayer.session = sessionManager.session
        }
        if let connection = uiView.videoPreviewLayer.connection {
            let previewAngle = sessionManager.rotationBridge.currentAngles.previewAngleDeg
            if connection.isVideoRotationAngleSupported(previewAngle) {
                connection.videoRotationAngle = previewAngle
            }
        }
    }
}

#else

/// Fallback preview representation for non-UIKit and testing environments.
public struct CameraPreviewView: View {
    public let sessionManager: CaptureSessionManager
    public let isSessionRunning: Bool

    public init(sessionManager: CaptureSessionManager, isSessionRunning: Bool = false) {
        self.sessionManager = sessionManager
        self.isSessionRunning = isSessionRunning
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Rectangle()
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                .padding(20)
            Text(isSessionRunning ? "Viewfinder Active" : "Viewfinder Preview")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.3))
        }
    }
}

#endif
