import SwiftUI
import CoreGraphics

#if canImport(UIKit)
import UIKit
#endif

import ComposeKit
import PerceptionKit

// MARK: - Hint Catalog Resolver

/// Resolves localized composition hints (`primary`, `secondary`, `spoken`) from built-in dictionaries
/// covering all 21 standard keys with zero runtime file I/O overhead.
public final class HintCatalogResolver: @unchecked Sendable {
    public static let shared = HintCatalogResolver()

    public let builtInZhHans: [String: ComposeHint] = [
        "rotate_cw": ComposeHint(primary: "手机顺时针转一点", secondary: "画面向左歪了", spoken: "手机顺时针转"),
        "rotate_ccw": ComposeHint(primary: "手机逆时针转一点", secondary: "画面向右歪了", spoken: "手机逆时针转"),
        "hold_vertical": ComposeHint(primary: "手机拿竖直", secondary: "避免人体和建筑透视变形", spoken: "手机拿正"),
        "lower_phone": ComposeHint(primary: "手机放低一点", secondary: "脚贴底边更显腿长", spoken: "手机放低"),
        "lower_and_vertical": ComposeHint(primary: "手机放低、保持竖直", secondary: "脚贴底边更显腿长", spoken: "手机放低拿正"),
        "step_back": ComposeHint(primary: "后退一步", secondary: "给人物留出更多空间", spoken: "后退一步"),
        "step_forward": ComposeHint(primary: "往前走一步", secondary: "主体在画面中太小", spoken: "往前走一步"),
        "pan_left": ComposeHint(primary: "镜头往左移一点", secondary: "为视线方向留出留白", spoken: "镜头往左"),
        "pan_right": ComposeHint(primary: "镜头往右移一点", secondary: "为视线方向留出留白", spoken: "镜头往右"),
        "tilt_down": ComposeHint(primary: "镜头往下移一点", secondary: "头顶上方留白过多", spoken: "镜头往下"),
        "tilt_up": ComposeHint(primary: "镜头往上抬一点", secondary: "头顶上方留白太挤", spoken: "镜头往上"),
        "switch_zoom_2x": ComposeHint(primary: "切到 2×，后退几步", secondary: "离太近脸部会有透视畸变", spoken: "切二倍后退"),
        "switch_zoom_step_back": ComposeHint(primary: "切到 2×，后退几步", secondary: "离太近脸部会有透视畸变", spoken: "切二倍后退"),
        "switch_zoom_1x": ComposeHint(primary: "切到 1× 拍摄", secondary: "超广角边缘人物易拉伸形变", spoken: "切到一倍"),
        "enable_fill": ComposeHint(primary: "点这里补光", secondary: "逆光人物脸部偏暗", spoken: "开启补光"),
        "move_to_shade": ComposeHint(primary: "移到阴凉处拍摄", secondary: "顶光过强产生面部阴影", spoken: "移到阴凉处"),
        "turn_subject_side": ComposeHint(primary: "人物侧身一点", secondary: "顺光直射五官缺乏立体感", spoken: "侧身一点"),
        "turn_face_to_light": ComposeHint(primary: "脸转向光线方向", secondary: "侧光过强产生阴阳脸", spoken: "脸转向光"),
        "use_night_mode": ComposeHint(primary: "开启夜景模式或移至光亮处", secondary: "环境光线过暗", spoken: "开启夜景"),
        "clean_lens": ComposeHint(primary: "请擦拭相机镜头", secondary: "镜头脏污会导致画面发雾眩光", spoken: "擦拭镜头"),
        "multi.occlusion": ComposeHint(primary: "错开站位，避免人物遮挡", secondary: "前后人物有重叠", spoken: "错开站位"),
        "multi.unbalanced": ComposeHint(primary: "移动镜头，居中多人站位", secondary: "人物整体偏向画面一侧", spoken: "居中站位"),
        "good": ComposeHint(primary: "构图不错，可以拍", secondary: "", spoken: "好，拍吧")
    ]

    public let builtInEn: [String: ComposeHint] = [
        "rotate_cw": ComposeHint(primary: "Rotate clockwise slightly", secondary: "Horizon tilted left", spoken: "Rotate clockwise"),
        "rotate_ccw": ComposeHint(primary: "Rotate counter-clockwise", secondary: "Horizon tilted right", spoken: "Rotate counter-clockwise"),
        "hold_vertical": ComposeHint(primary: "Hold phone upright", secondary: "Avoid perspective distortion", spoken: "Hold upright"),
        "lower_phone": ComposeHint(primary: "Lower phone slightly", secondary: "Feet near bottom edge for longer legs", spoken: "Lower phone"),
        "lower_and_vertical": ComposeHint(primary: "Lower phone, hold upright", secondary: "Feet near bottom edge for longer legs", spoken: "Lower phone and level"),
        "step_back": ComposeHint(primary: "Step back", secondary: "Subject cropped or too close", spoken: "Step back"),
        "step_forward": ComposeHint(primary: "Step forward", secondary: "Subject too small in frame", spoken: "Step forward"),
        "pan_left": ComposeHint(primary: "Pan left a bit", secondary: "Leave room in facing direction", spoken: "Pan left"),
        "pan_right": ComposeHint(primary: "Pan right a bit", secondary: "Leave room in facing direction", spoken: "Pan right"),
        "tilt_down": ComposeHint(primary: "Tilt down slightly", secondary: "Too much headroom", spoken: "Tilt down"),
        "tilt_up": ComposeHint(primary: "Tilt up slightly", secondary: "Head too close to top edge", spoken: "Tilt up"),
        "switch_zoom_2x": ComposeHint(primary: "Switch to 2x, step back", secondary: "Avoid wide-angle facial distortion", spoken: "Switch to 2x"),
        "switch_zoom_step_back": ComposeHint(primary: "Switch to 2x, step back", secondary: "Avoid wide-angle facial distortion", spoken: "Switch to 2x"),
        "switch_zoom_1x": ComposeHint(primary: "Switch to 1x", secondary: "Subject near edge of ultra-wide lens causes distortion", spoken: "Switch to 1x"),
        "enable_fill": ComposeHint(primary: "Tap to fill light", secondary: "Subject face is backlit and dark", spoken: "Enable fill light"),
        "move_to_shade": ComposeHint(primary: "Move subject into shade", secondary: "Harsh overhead light creates dark shadows", spoken: "Move into shade"),
        "turn_subject_side": ComposeHint(primary: "Turn subject slightly to the side", secondary: "Direct frontal light creates flat features", spoken: "Turn slightly"),
        "turn_face_to_light": ComposeHint(primary: "Turn face toward the light", secondary: "Harsh side light creates uneven shadows", spoken: "Face the light"),
        "use_night_mode": ComposeHint(primary: "Use Night Mode or find brighter light", secondary: "Ambient light is too dim", spoken: "Use Night Mode"),
        "clean_lens": ComposeHint(primary: "Clean your camera lens", secondary: "Smudged lens causes haze and glare", spoken: "Clean lens"),
        "multi.occlusion": ComposeHint(primary: "Step aside to avoid overlap", secondary: "Subjects are overlapping in frame", spoken: "Avoid overlap"),
        "multi.unbalanced": ComposeHint(primary: "Center the group in frame", secondary: "Group is positioned toward one side", spoken: "Center group"),
        "good": ComposeHint(primary: "Great composition, take the shot", secondary: "", spoken: "Ready, shoot")
    ]

    public init() {}

    public func resolve(hintKey: String?, locale: String = "zh-Hans", fallbackHint: ComposeHint? = nil) -> ComposeHint {
        guard let key = hintKey, !key.isEmpty else {
            return fallbackHint ?? ComposeHint(primary: "构图不错，可以拍", secondary: "", spoken: "好，拍吧")
        }

        let dict = locale.lowercased().starts(with: "en") ? builtInEn : builtInZhHans
        if let match = dict[key] {
            return match
        }

        if let fb = fallbackHint, !fb.primary.isEmpty {
            return fb
        }

        return ComposeHint(primary: key, secondary: "", spoken: key)
    }
}

// MARK: - Guidance Haptic Engine

/// Manages throttled light impact haptics when entering good composition or level horizon alignment.
@MainActor
public final class GuidanceHapticEngine: ObservableObject {
    public let cooldownInterval: TimeInterval
    public private(set) var goodToShootHapticCount: Int = 0
    public private(set) var levelHapticCount: Int = 0

    private var wasGoodToShoot: Bool = false
    private var wasLevel: Bool = false
    private var lastGoodHapticTime: TimeInterval = -100.0
    private var lastLevelHapticTime: TimeInterval = -100.0

    #if canImport(UIKit) && os(iOS)
    private var generator: UIImpactFeedbackGenerator? = UIImpactFeedbackGenerator(style: .light)
    #endif

    public init(cooldownInterval: TimeInterval = 2.0) {
        self.cooldownInterval = cooldownInterval
        #if canImport(UIKit) && os(iOS)
        generator?.prepare()
        #endif
    }

    /// Evaluates transitions and triggers light impact haptics on edge state changes.
    public func evaluateTransition(
        isGoodToShoot: Bool,
        rollDeg: Double,
        pitchDeg: Double = 0.0,
        isFlatish: Bool = false,
        currentTime: TimeInterval = CFAbsoluteTimeGetCurrent()
    ) {
        let isLevel = !isFlatish && abs(rollDeg) <= 1.0

        // 1. Transition into Good-to-shoot
        if isGoodToShoot && !wasGoodToShoot {
            if currentTime - lastGoodHapticTime >= cooldownInterval {
                triggerHaptic()
                goodToShootHapticCount += 1
                lastGoodHapticTime = currentTime
            }
        }
        wasGoodToShoot = isGoodToShoot

        // 2. Transition into Horizon Level
        if isLevel && !wasLevel {
            if currentTime - lastLevelHapticTime >= cooldownInterval {
                triggerHaptic()
                levelHapticCount += 1
                lastLevelHapticTime = currentTime
            }
        }
        wasLevel = isLevel
    }

    public func triggerHaptic() {
        #if canImport(UIKit) && os(iOS)
        generator?.impactOccurred()
        generator?.prepare()
        #endif
    }

    public func reset() {
        wasGoodToShoot = false
        wasLevel = false
        lastGoodHapticTime = -100.0
        lastLevelHapticTime = -100.0
        goodToShootHapticCount = 0
        levelHapticCount = 0
    }
}

// MARK: - Horizon Indicator View

/// High-precision dynamic horizon level indicator with reference notches and degree badge.
public struct HorizonIndicatorView: View {
    public let rollDeg: Double
    public let pitchDeg: Double
    public let isFlatish: Bool

    public init(rollDeg: Double, pitchDeg: Double = 0.0, isFlatish: Bool = false) {
        self.rollDeg = rollDeg
        self.pitchDeg = pitchDeg
        self.isFlatish = isFlatish
    }

    private var isLevel: Bool {
        abs(rollDeg) <= 1.0
    }

    private var indicatorColor: Color {
        let absRoll = abs(rollDeg)
        if absRoll <= 1.0 {
            return .green
        } else if absRoll <= 2.5 {
            return .yellow
        } else {
            return .red
        }
    }

    public var body: some View {
        GeometryReader { proxy in
            if !isFlatish {
                let center = CGPoint(x: proxy.size.width / 2.0, y: proxy.size.height / 2.0)
                let lineWidth: CGFloat = proxy.size.width * 0.35

                ZStack {
                    // Left and right fixed horizontal reference notches
                    HStack {
                        Rectangle()
                            .fill(Color.white.opacity(0.4))
                            .frame(width: 24, height: 2)
                        Spacer()
                        Rectangle()
                            .fill(Color.white.opacity(0.4))
                            .frame(width: 24, height: 2)
                    }
                    .frame(width: proxy.size.width * 0.55)
                    .position(center)

                    // Rotating dynamic level line
                    Rectangle()
                        .fill(indicatorColor)
                        .frame(width: lineWidth, height: isLevel ? 2.5 : 2)
                        .rotationEffect(.degrees(rollDeg))
                        .position(center)
                        .animation(.easeOut(duration: 0.1), value: rollDeg)

                    // Degree badge when tilted > 0.5°
                    if abs(rollDeg) > 0.5 {
                        Text(String(format: "%+.1f°", rollDeg))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(indicatorColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.7))
                            .clipShape(Capsule())
                            .position(x: center.x, y: center.y - 24)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Hint Pill View

/// Single active composition guidance pill displaying primary and secondary hints,
/// severity-based color coding, audience icon, and optional quick-zoom button.
public struct HintPillView: View {
    public let hint: ComposeHint
    public let severity: ComposeSeverity
    public let primaryAction: ComposeAction?
    public let isSilent: Bool
    public let onSelectZoom: ((Float) -> Void)?

    public init(
        hint: ComposeHint,
        severity: ComposeSeverity = .good,
        primaryAction: ComposeAction? = nil,
        isSilent: Bool = false,
        onSelectZoom: ((Float) -> Void)? = nil
    ) {
        self.hint = hint
        self.severity = severity
        self.primaryAction = primaryAction
        self.isSilent = isSilent
        self.onSelectZoom = onSelectZoom
    }

    private var pillColor: Color {
        switch severity {
        case .critical:
            return .red
        case .major:
            return .orange
        case .minor:
            return .yellow
        case .good:
            return .green
        }
    }

    private var actionSymbolName: String {
        guard let action = primaryAction else {
            return "checkmark.circle.fill"
        }
        switch action {
        case .rotate:
            return "arrow.triangle.2.circlepath"
        case .holdVertical:
            return "iphone"
        case .lowerPhone:
            return "arrow.down"
        case .stepBack:
            return "arrow.down.forward.and.arrow.up.backward"
        case .stepForward:
            return "arrow.up.left.and.arrow.down.right"
        case .panLeft:
            return "arrow.left"
        case .panRight:
            return "arrow.right"
        case .tiltUp:
            return "arrow.up"
        case .tiltDown:
            return "arrow.down"
        case .switchZoom:
            return "camera.aperture"
        case .enableFill:
            return "sun.max.fill"
        case .cleanLens:
            return "sparkles"
        case .moveToShade:
            return "cloud.sun.fill"
        case .turnSubject:
            return "person.crop.circle.badge.checkmark"
        case .useNightMode:
            return "moon.stars.fill"
        case .good:
            return "checkmark.circle.fill"
        }
    }

    public var body: some View {
        if !isSilent && !hint.primary.isEmpty {
            HStack(spacing: 10) {
                // Action Symbol
                Image(systemName: actionSymbolName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(pillColor)

                // Text Content
                VStack(alignment: .leading, spacing: 2) {
                    Text(hint.primary)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)

                    if !hint.secondary.isEmpty {
                        Text(hint.secondary)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }

                // Interactive Quick-Zoom Button
                if case let .switchZoom(factor) = primaryAction {
                    Button(action: {
                        onSelectZoom?(factor)
                    }) {
                        Text(factor.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "切到 %.0fx", factor) : String(format: "切到 %.1fx", factor))
                            .font(.system(size: 12, weight: .black))
                            .foregroundColor(.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.yellow)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.75))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(pillColor.opacity(0.7), lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: Color.black.opacity(0.4), radius: 6, x: 0, y: 3)
            .animation(.easeInOut(duration: 0.25), value: hint.primary)
        }
    }
}

// MARK: - Target Line Overlay

/// Dynamic composition guides including rule-of-thirds grid, foot target line,
/// headroom target line, and directional guidance arrows.
public struct TargetLineOverlay: View {
    public let output: ComposeOutput
    public let boundingBox: CGRect?

    public init(output: ComposeOutput, boundingBox: CGRect? = nil) {
        self.output = output
        self.boundingBox = boundingBox
    }

    public var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height

            ZStack {
                // 1. Rule-of-thirds grid
                Path { path in
                    path.move(to: CGPoint(x: w / 3.0, y: 0))
                    path.addLine(to: CGPoint(x: w / 3.0, y: h))
                    path.move(to: CGPoint(x: 2.0 * w / 3.0, y: 0))
                    path.addLine(to: CGPoint(x: 2.0 * w / 3.0, y: h))

                    path.move(to: CGPoint(x: 0, y: h / 3.0))
                    path.addLine(to: CGPoint(x: w, y: h / 3.0))
                    path.move(to: CGPoint(x: 0, y: 2.0 * h / 3.0))
                    path.addLine(to: CGPoint(x: w, y: 2.0 * h / 3.0))
                }
                .stroke(Color.white.opacity(0.12), lineWidth: 1)

                // 2. Foot Target Line (feet.floating / lower_phone)
                if shouldShowFootTargetLine {
                    let footY = h * 0.90
                    Path { path in
                        path.move(to: CGPoint(x: w * 0.15, y: footY))
                        path.addLine(to: CGPoint(x: w * 0.85, y: footY))
                    }
                    .stroke(Color.green.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))

                    Text("脚贴底边")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Capsule())
                        .position(x: w / 2.0, y: footY - 14)
                }

                // 3. Headroom Target Line (headroom.* / crop.head)
                if shouldShowHeadroomTargetLine {
                    let headY = h * 0.16
                    Path { path in
                        path.move(to: CGPoint(x: w * 0.2, y: headY))
                        path.addLine(to: CGPoint(x: w * 0.8, y: headY))
                    }
                    .stroke(Color.yellow.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

                    Text("理想头顶位置")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.yellow)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Capsule())
                        .position(x: w / 2.0, y: headY - 12)
                }

                // 4. Directional Action Arrows
                directionalArrow(size: proxy.size)
            }
        }
        .allowsHitTesting(false)
    }

    private var shouldShowFootTargetLine: Bool {
        let key = output.hintKey ?? ""
        return key == "lower_phone" || key == "lower_and_vertical" ||
            output.primaryAction == .lowerPhone || output.secondaryAction == .lowerPhone
    }

    private var shouldShowHeadroomTargetLine: Bool {
        let key = output.hintKey ?? ""
        let finding = output.activeFindingId ?? ""
        return key == "tilt_up" || key == "tilt_down" || finding.contains("headroom") || finding.contains("head_crop")
    }

    @ViewBuilder
    private func directionalArrow(size: CGSize) -> some View {
        if let action = output.primaryAction {
            switch action {
            case .panLeft:
                Image(systemName: "arrow.left.circle.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.yellow)
                    .position(x: 44, y: size.height / 2.0)
            case .panRight:
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.yellow)
                    .position(x: size.width - 44, y: size.height / 2.0)
            case .tiltUp:
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.yellow)
                    .position(x: size.width / 2.0, y: size.height * 0.28)
            case .tiltDown:
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.yellow)
                    .position(x: size.width / 2.0, y: size.height * 0.72)
            default:
                EmptyView()
            }
        }
    }
}

// MARK: - Good To Shoot Overlay

/// Pulsing green breathing confirmation frame and subject box outline when composition is optimal.
public struct GoodToShootOverlay: View {
    public let isGoodToShoot: Bool
    public let boundingBox: CGRect?
    @State private var isBreathing: Bool = false

    public init(isGoodToShoot: Bool, boundingBox: CGRect? = nil) {
        self.isGoodToShoot = isGoodToShoot
        self.boundingBox = boundingBox
    }

    public var body: some View {
        GeometryReader { proxy in
            if isGoodToShoot {
                ZStack {
                    // Outer viewfinder glow border
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.green, lineWidth: 3)
                        .opacity(isBreathing ? 0.9 : 0.4)
                        .padding(12)
                        .onDisappear {
                            isBreathing = false
                        }

                    // Bounding box glow outline
                    if let box = boundingBox {
                        let rect = CGRect(
                            x: box.origin.x * proxy.size.width,
                            y: box.origin.y * proxy.size.height,
                            width: box.size.width * proxy.size.width,
                            height: box.size.height * proxy.size.height
                        )
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.green, lineWidth: 2.5)
                            .opacity(isBreathing ? 1.0 : 0.6)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    }
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        isBreathing = true
                    }
                }
                .onDisappear {
                    isBreathing = false
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Multi-Subject Framing Overlay

/// Multi-subject framing overlays rendering primary/secondary subject bounding boxes,
/// role badges, occlusion warnings, and group balance auxiliary guidelines.
public struct MultiSubjectFramingOverlay: View {
    public let subjectBoxes: [SubjectOverlayBox]
    public let activeHintKey: String

    public init(subjectBoxes: [SubjectOverlayBox], activeHintKey: String) {
        self.subjectBoxes = subjectBoxes
        self.activeHintKey = activeHintKey
    }

    private var isMultiOcclusion: Bool {
        activeHintKey == "multi.occlusion"
    }

    private var isMultiUnbalanced: Bool {
        activeHintKey == "multi.unbalanced"
    }

    public var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height

            ZStack {
                // 1. Spacing balance auxiliary lines when unbalanced and count >= 2
                if subjectBoxes.count >= 2 && isMultiUnbalanced {
                    // Vertical frame center reference at 0.5 * width
                    Path { path in
                        path.move(to: CGPoint(x: w * 0.5, y: 0))
                        path.addLine(to: CGPoint(x: w * 0.5, y: h))
                    }
                    .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))

                    let centers = subjectBoxes.map { box in
                        CGPoint(
                            x: (box.rect.origin.x + box.rect.width * 0.5) * w,
                            y: (box.rect.origin.y + box.rect.height * 0.5) * h
                        )
                    }
                    let comX = centers.map(\.x).reduce(0, +) / CGFloat(centers.count)
                    let comY = centers.map(\.y).reduce(0, +) / CGFloat(centers.count)

                    // Horizontal span line between leftmost and rightmost subject centers
                    if let minXCenter = centers.min(by: { $0.x < $1.x }),
                       let maxXCenter = centers.max(by: { $0.x < $1.x }) {
                        Path { path in
                            path.move(to: CGPoint(x: minXCenter.x, y: comY))
                            path.addLine(to: CGPoint(x: maxXCenter.x, y: comY))
                        }
                        .stroke(Color.yellow.opacity(0.85), style: StrokeStyle(lineWidth: 2, dash: [6, 3]))

                        // Vertical tick endpoints
                        Path { path in
                            path.move(to: CGPoint(x: minXCenter.x, y: comY - 6))
                            path.addLine(to: CGPoint(x: minXCenter.x, y: comY + 6))
                            path.move(to: CGPoint(x: maxXCenter.x, y: comY - 6))
                            path.addLine(to: CGPoint(x: maxXCenter.x, y: comY + 6))
                        }
                        .stroke(Color.yellow.opacity(0.85), lineWidth: 2)
                    }

                    // Group center-of-mass marker
                    Circle()
                        .fill(Color.yellow)
                        .frame(width: 8, height: 8)
                        .position(x: comX, y: comY)

                    Circle()
                        .stroke(Color.yellow, lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                        .position(x: comX, y: comY)

                    Text("重心")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.yellow)
                        .clipShape(Capsule())
                        .position(x: comX, y: comY - 16)
                }

                // 2. Framing overlays for each subject box
                ForEach(subjectBoxes) { box in
                    let rect = CGRect(
                        x: box.rect.origin.x * w,
                        y: box.rect.origin.y * h,
                        width: box.rect.width * w,
                        height: box.rect.height * h
                    )

                    if box.isPrimary {
                        // Primary subject: green/cyan solid border + "主" badge when subjectBoxes.count > 1
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.cyan, lineWidth: 2)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)

                        if subjectBoxes.count > 1 {
                            Text("主")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.cyan)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .position(x: rect.minX + 12, y: max(rect.minY - 10, 10))
                        }
                    } else {
                        // Secondary subjects: amber/orange dashed border;
                        // if activeHintKey == "multi.occlusion", highlight in red with "遮挡" badge.
                        if isMultiOcclusion {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.red, lineWidth: 2)
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)

                            Text("遮挡")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.red)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .position(x: rect.minX + 16, y: max(rect.minY - 10, 10))
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.orange, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - User Guidance HUD (Unified Container)

/// Unified interactive composition guidance HUD integrating the horizon level indicator,
/// target lines, multi-subject framing overlays, breathing good-to-shoot frame, and the active hint pill.
public struct UserGuidanceHUD: View {
    @Binding public var isEnabled: Bool
    public let output: ComposeOutput
    public let hint: ComposeHint
    public let rollDeg: Double
    public let pitchDeg: Double
    public let boundingBox: CGRect?
    public let subjectBoxes: [SubjectOverlayBox]
    public let isFlatish: Bool
    public let isEngineDegraded: Bool
    public let onSelectZoom: ((Float) -> Void)?

    public init(
        isEnabled: Binding<Bool>,
        output: ComposeOutput,
        hint: ComposeHint,
        rollDeg: Double,
        pitchDeg: Double = 0.0,
        boundingBox: CGRect? = nil,
        subjectBoxes: [SubjectOverlayBox] = [],
        isFlatish: Bool = false,
        isEngineDegraded: Bool = false,
        onSelectZoom: ((Float) -> Void)? = nil
    ) {
        self._isEnabled = isEnabled
        self.output = output
        self.hint = hint
        self.rollDeg = rollDeg
        self.pitchDeg = pitchDeg
        self.boundingBox = boundingBox
        self.subjectBoxes = subjectBoxes
        self.isFlatish = isFlatish
        self.isEngineDegraded = isEngineDegraded
        self.onSelectZoom = onSelectZoom
    }

    public var activeHintKey: String {
        if output.hintKey == "multi.occlusion" || output.activeFindingId == "multi.occlusion" {
            return "multi.occlusion"
        }
        if output.hintKey == "multi.unbalanced" || output.activeFindingId == "multi.unbalanced" {
            return "multi.unbalanced"
        }
        return output.hintKey ?? output.activeFindingId ?? ""
    }

    public var body: some View {
        if isEnabled {
            ZStack {
                // 1. Target Lines and Thirds Grid
                TargetLineOverlay(output: output, boundingBox: boundingBox)
                    .allowsHitTesting(false)

                // 2. Horizon Level Line & Reference Notches
                HorizonIndicatorView(rollDeg: rollDeg, pitchDeg: pitchDeg, isFlatish: isFlatish)
                    .allowsHitTesting(false)

                // 3. Multi-Subject Framing Overlays (Primary, Secondary, Occlusion & Balance lines)
                if !subjectBoxes.isEmpty {
                    MultiSubjectFramingOverlay(subjectBoxes: subjectBoxes, activeHintKey: activeHintKey)
                        .allowsHitTesting(false)
                }

                // 4. Good-to-shoot confirmation overlay
                GoodToShootOverlay(isGoodToShoot: output.isGoodToShoot, boundingBox: subjectBoxes.isEmpty ? boundingBox : nil)
                    .allowsHitTesting(false)

                // 5. Engine Degraded Warning Capsule
                if isEngineDegraded {
                    VStack {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.black)
                            Text("构图引擎受限，仅基础取景")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.black)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.yellow)
                        .clipShape(Capsule())
                        .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
                        .padding(.top, 96)

                        Spacer()
                    }
                    .allowsHitTesting(false)
                }

                // 6. Active Hint Pill
                VStack {
                    Spacer()
                    HintPillView(
                        hint: hint,
                        severity: output.severity,
                        primaryAction: output.primaryAction,
                        isSilent: false,
                        onSelectZoom: onSelectZoom
                    )
                    .padding(.bottom, 110)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(true)
        }
    }
}
