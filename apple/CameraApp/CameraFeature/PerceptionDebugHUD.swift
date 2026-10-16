import SwiftUI
import CoreGraphics

#if canImport(PerceptionKit)
import PerceptionKit
#endif

/// Telemetry metrics displayed on the Perception Debug HUD.
public struct DebugTelemetry: Sendable, Equatable {
    public var fps: Double
    public var latencyMs: Double
    public var rollDeg: Double
    public var pitchDeg: Double
    public var activeFindingId: String?
    public var hintKey: String?
    public var thermalState: String
    public var subjectCount: Int

    public init(
        fps: Double = 60.0,
        latencyMs: Double = 4.7,
        rollDeg: Double = 0.0,
        pitchDeg: Double = 0.0,
        activeFindingId: String? = nil,
        hintKey: String? = "good",
        thermalState: String = "nominal",
        subjectCount: Int = 1
    ) {
        self.fps = fps
        self.latencyMs = latencyMs
        self.rollDeg = rollDeg
        self.pitchDeg = pitchDeg
        self.activeFindingId = activeFindingId
        self.hintKey = hintKey
        self.thermalState = thermalState
        self.subjectCount = subjectCount
    }
}

/// A normalized joint coordinate for rendering.
public struct RenderJoint: Identifiable, Sendable {
    public let id: String
    public let x: CGFloat
    public let y: CGFloat
    public let confidence: Float

    public init(id: String, x: CGFloat, y: CGFloat, confidence: Float = 1.0) {
        self.id = id
        self.x = x
        self.y = y
        self.confidence = confidence
    }
}

/// Standard bone connections between keypoints (supports canonical PascalCase and shorthand keys).
public let StandardSkeletalBones: [(from: String, to: String)] = [
    ("Nose", "Neck"),
    ("Neck", "Root"),
    ("Neck", "LeftShoulder"),
    ("Neck", "RightShoulder"),
    ("LeftShoulder", "LeftElbow"),
    ("LeftElbow", "LeftWrist"),
    ("RightShoulder", "RightElbow"),
    ("RightElbow", "RightWrist"),
    ("Root", "LeftHip"),
    ("Root", "RightHip"),
    ("LeftHip", "LeftKnee"),
    ("LeftKnee", "LeftAnkle"),
    ("RightHip", "RightKnee"),
    ("RightKnee", "RightAnkle"),
    ("nose", "neck"),
    ("neck", "root"),
    ("neck", "lShoulder"),
    ("neck", "rShoulder"),
    ("lShoulder", "lElbow"),
    ("lElbow", "lWrist"),
    ("rShoulder", "rElbow"),
    ("rElbow", "rWrist"),
    ("root", "lHip"),
    ("root", "rHip"),
    ("lHip", "lKnee"),
    ("lKnee", "lAnkle"),
    ("rHip", "rKnee"),
    ("rKnee", "rAnkle")
]

/// Ultra-low-overhead SwiftUI HUD overlay for visual debugging of body poses,
/// bounding boxes, horizon level lines, and perception latency.
public struct PerceptionDebugHUD: View {
    @Binding public var isVisible: Bool
    public let telemetry: DebugTelemetry
    public let joints: [String: RenderJoint]
    public let boundingBox: CGRect? // In normalized [0, 1] UI space

    public init(
        isVisible: Binding<Bool>,
        telemetry: DebugTelemetry,
        joints: [String: RenderJoint] = [:],
        boundingBox: CGRect? = nil
    ) {
        self._isVisible = isVisible
        self.telemetry = telemetry
        self.joints = joints
        self.boundingBox = boundingBox
    }

    public var body: some View {
        GeometryReader { proxy in
            if isVisible {
                ZStack {
                    // 1. Skeletal bones and joint dots
                    canvasOverlay(size: proxy.size)

                    // 2. Horizon Level Line
                    horizonLevelIndicator(size: proxy.size)

                    // 3. Telemetry Info Card
                    VStack {
                        Spacer()
                        HStack {
                            telemetryCard
                            Spacer()
                        }
                    }
                    .padding(16)
                }
            }

            // Always-visible HUD toggle button in top-trailing corner
            VStack {
                HStack {
                    Spacer()
                    Button(action: { isVisible.toggle() }) {
                        Image(systemName: isVisible ? "eye.fill" : "eye.slash.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .padding(12)
                }
                Spacer()
            }
        }
    }

    // MARK: - Canvas Rendering

    @ViewBuilder
    private func canvasOverlay(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            // Render Bounding Box
            if let box = boundingBox {
                let rect = CGRect(
                    x: box.origin.x * canvasSize.width,
                    y: box.origin.y * canvasSize.height,
                    width: box.size.width * canvasSize.width,
                    height: box.size.height * canvasSize.height
                )
                let boxPath = Path(roundedRect: rect, cornerRadius: 8)
                let strokeColor = (telemetry.activeFindingId == nil) ? Color.green : Color.yellow
                context.stroke(boxPath, with: .color(strokeColor), lineWidth: 2)
            }

            // Render Skeleton Bones
            for bone in StandardSkeletalBones {
                if let j1 = joints[bone.from], let j2 = joints[bone.to],
                   j1.confidence >= 0.3, j2.confidence >= 0.3 {
                    var line = Path()
                    line.move(to: CGPoint(x: j1.x * canvasSize.width, y: j1.y * canvasSize.height))
                    line.addLine(to: CGPoint(x: j2.x * canvasSize.width, y: j2.y * canvasSize.height))
                    context.stroke(line, with: .color(Color.cyan.opacity(0.8)), lineWidth: 3)
                }
            }

            // Render Joint Circles
            for (_, joint) in joints where joint.confidence >= 0.3 {
                let center = CGPoint(x: joint.x * canvasSize.width, y: joint.y * canvasSize.height)
                let dot = Path(ellipseIn: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8))
                context.fill(dot, with: .color(Color.yellow))
                context.stroke(dot, with: .color(Color.black), lineWidth: 1)
            }
        }
    }

    // MARK: - Horizon Level

    @ViewBuilder
    private func horizonLevelIndicator(size: CGSize) -> some View {
        let isLevel = abs(telemetry.rollDeg) < 1.0
        let indicatorColor = isLevel ? Color.green : Color.red

        Rectangle()
            .fill(indicatorColor)
            .frame(width: size.width * 0.4, height: 2)
            .rotationEffect(.degrees(telemetry.rollDeg))
            .position(x: size.width / 2.0, y: size.height / 2.0)
            .opacity(0.8)
    }

    // MARK: - Telemetry Card

    private var telemetryCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PERCEPTION HUD")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(.yellow)

            HStack(spacing: 8) {
                Label("\(Int(telemetry.fps)) FPS", systemImage: "speedometer")
                Label(String(format: "%.1f ms", telemetry.latencyMs), systemImage: "clock")
            }
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(.white)

            HStack(spacing: 8) {
                Text(String(format: "Roll: %+.1f°", telemetry.rollDeg))
                Text(String(format: "Pitch: %+.1f°", telemetry.pitchDeg))
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.white.opacity(0.8))

            if let finding = telemetry.activeFindingId {
                Text("Finding: \(finding)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.orange)
            } else {
                Text("Finding: None (Good to shoot)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.green)
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.75))
        .cornerRadius(8)
    }
}
