import Foundation
import SwiftUI

#if canImport(AVFAudio)
import AVFAudio
#elseif canImport(AVFoundation)
import AVFoundation
#endif

#if canImport(UIKit)
import UIKit
#endif

import ComposeKit

// MARK: - Voice Prompter Configuration

/// Timing, volume, and speech rate tuning parameters for composition voice prompts.
public struct VoicePrompterConfig: Sendable, Equatable {
    /// Minimum cooldown interval between any spoken prompts (default: 2.0s).
    public var minIntervalSec: Double

    /// Cooldown window before the same composition hint may be re-spoken (default: 4.5s).
    public var sameHintCooldownSec: Double

    /// Minimum duration to wait before repeating an identical ongoing hint (default: 6.0s).
    public var repeatAfterSec: Double

    /// Maximum number of times an unchanged ongoing hint may be repeated (default: 1).
    public var maxRepeats: Int

    /// Quiet window around photo capture to suppress speech and prevent mic/audio interference (default: 1.5s).
    public var captureQuietWindowSec: Double

    /// AVSpeechUtterance rate (default: 0.52).
    public var rate: Float

    /// AVSpeechUtterance volume (default: 0.9).
    public var volume: Float

    /// BCP-47 speech synthesis language tag (default: "zh-CN").
    public var languageCode: String

    /// Whether to announce successful composition ("好，拍吧") (default: true).
    public var speakGood: Bool

    public init(
        minIntervalSec: Double = 2.0,
        sameHintCooldownSec: Double = 4.5,
        repeatAfterSec: Double = 6.0,
        maxRepeats: Int = 1,
        captureQuietWindowSec: Double = 1.5,
        rate: Float = 0.52,
        volume: Float = 0.9,
        languageCode: String = "zh-CN",
        speakGood: Bool = true
    ) {
        self.minIntervalSec = minIntervalSec
        self.sameHintCooldownSec = sameHintCooldownSec
        self.repeatAfterSec = repeatAfterSec
        self.maxRepeats = maxRepeats
        self.captureQuietWindowSec = captureQuietWindowSec
        self.rate = rate
        self.volume = volume
        self.languageCode = languageCode
        self.speakGood = speakGood
    }

    public static let `default` = VoicePrompterConfig()
}

// MARK: - Voice Prompter Decisions & Suppressions

/// Explicit suppression reason explaining why an utterance was withheld.
public enum VoiceSuppressionReason: String, Sendable, Equatable {
    case muted
    case voiceOverActive
    case shutterQuietWindow
    case emptyHint
    case duplicateGood
    case sameHintCooldown
    case minIntervalCooldown
    case maxRepeatsReached
}

/// Outcome of evaluating an incoming composition output for speech.
public enum VoicePromptDecision: Equatable, Sendable {
    case spoken(String)
    case spokenInterrupted(String)
    case suppressed(VoiceSuppressionReason)

    public var isSpoken: Bool {
        switch self {
        case .spoken, .spokenInterrupted:
            return true
        case .suppressed:
            return false
        }
    }
}

/// Immutable historical record of a spoken voice prompt.
public struct VoiceUtteranceRecord: Sendable, Equatable {
    public let text: String
    public let hintKey: String
    public let timestamp: Double
    public let repeatCount: Int
    public let isInterrupted: Bool

    public init(
        text: String,
        hintKey: String,
        timestamp: Double,
        repeatCount: Int,
        isInterrupted: Bool
    ) {
        self.text = text
        self.hintKey = hintKey
        self.timestamp = timestamp
        self.repeatCount = repeatCount
        self.isInterrupted = isInterrupted
    }
}

// MARK: - Voice Prompter

/// Real-time audio voice prompter announcing composition adjustments and good-to-shoot signals.
///
/// Features:
/// 1. Mute toggle (`isEnabled`) which terminates any ongoing utterance immediately.
/// 2. Automatic deference when Apple VoiceOver is running (`UIAccessibility.isVoiceOverRunning`).
/// 3. Capture quiet window suppression before and after photo shutter firing.
/// 4. Same-hint deduplication cooldown and repeat limits (no consecutive "good" announcements).
/// 5. Global minimum interval enforcement with `.critical` finding priority interruption.
@MainActor
public final class VoicePrompter: ObservableObject {
    public var config: VoicePrompterConfig

    @Published public var isEnabled: Bool {
        didSet {
            if !isEnabled {
                stopSpeakingImmediate()
            }
        }
    }

    @Published public var lastSpokenText: String? = nil
    @Published public var lastDecision: VoicePromptDecision? = nil
    @Published public var totalSpokenCount: Int = 0
    @Published public var totalSuppressedCount: Int = 0

    public private(set) var lastSpokenRecord: VoiceUtteranceRecord? = nil
    public private(set) var lastSpokenTimestamp: Double = -100.0
    public private(set) var lastCaptureStartedTimestamp: Double = -100.0
    public private(set) var lastCaptureEndedTimestamp: Double = -100.0
    public private(set) var isCapturingPhoto: Bool = false

    private var currentHintRepeatCount: Int = 0
    private var lastSpokenTimeByKey: [String: Double] = [:]

    #if canImport(AVFAudio) || canImport(AVFoundation)
    private let synthesizer: AVSpeechSynthesizer = AVSpeechSynthesizer()
    #endif

    // MARK: - Built-in Spoken Tables (All 21 canonical hint keys)

    public static let chineseSpokenTable: [String: String] = [
        "rotate_cw": "手机顺时针转",
        "rotate_ccw": "手机逆时针转",
        "hold_vertical": "手机拿正",
        "lower_phone": "手机放低",
        "lower_and_vertical": "手机放低拿正",
        "step_back": "后退一步",
        "step_forward": "往前走一步",
        "pan_left": "镜头往左",
        "pan_right": "镜头往右",
        "tilt_down": "镜头往下",
        "tilt_up": "镜头往上",
        "switch_zoom_2x": "切二倍后退",
        "switch_zoom_step_back": "切二倍后退",
        "switch_zoom_1x": "切到一倍",
        "enable_fill": "开启补光",
        "move_to_shade": "移到阴凉处",
        "turn_subject_side": "侧身一点",
        "turn_face_to_light": "脸转向光",
        "use_night_mode": "开启夜景",
        "clean_lens": "擦拭镜头",
        "good": "好，拍吧"
    ]

    public static let englishSpokenTable: [String: String] = [
        "rotate_cw": "Rotate clockwise",
        "rotate_ccw": "Rotate counter-clockwise",
        "hold_vertical": "Hold upright",
        "lower_phone": "Lower phone",
        "lower_and_vertical": "Lower phone and level",
        "step_back": "Step back",
        "step_forward": "Step forward",
        "pan_left": "Pan left",
        "pan_right": "Pan right",
        "tilt_down": "Tilt down",
        "tilt_up": "Tilt up",
        "switch_zoom_2x": "Switch to 2x",
        "switch_zoom_step_back": "Switch to 2x",
        "switch_zoom_1x": "Switch to 1x",
        "enable_fill": "Enable fill light",
        "move_to_shade": "Move into shade",
        "turn_subject_side": "Turn slightly",
        "turn_face_to_light": "Face the light",
        "use_night_mode": "Use Night Mode",
        "clean_lens": "Clean lens",
        "good": "Ready, shoot"
    ]

    // MARK: - Initializer

    public init(
        config: VoicePrompterConfig = .default,
        isEnabled: Bool = true
    ) {
        self.config = config
        self.isEnabled = isEnabled
    }

    // MARK: - Capture Notifications

    /// Signals that a still photograph capture sequence has commenced.
    public func notifyCaptureStarted(at timestamp: Double = CFAbsoluteTimeGetCurrent()) {
        self.isCapturingPhoto = true
        self.lastCaptureStartedTimestamp = timestamp
        stopSpeakingImmediate()
    }

    /// Signals that a photograph capture sequence has completed.
    public func notifyCaptureEnded(at timestamp: Double = CFAbsoluteTimeGetCurrent()) {
        self.isCapturingPhoto = false
        self.lastCaptureEndedTimestamp = timestamp
    }

    /// Halts ongoing speech playback immediately.
    public func stopSpeakingImmediate() {
        #if canImport(AVFAudio) || canImport(AVFoundation)
        synthesizer.stopSpeaking(at: .immediate)
        #endif
    }

    /// Toggles voice speech enabled / muted state.
    @discardableResult
    public func toggleMute() -> Bool {
        isEnabled.toggle()
        return isEnabled
    }

    /// Explicitly updates voice speech enabled / muted state.
    public func setEnabled(_ enabled: Bool) {
        self.isEnabled = enabled
    }

    /// Resets all internal cooldown timers and utterance history.
    public func reset() {
        stopSpeakingImmediate()
        lastSpokenRecord = nil
        lastSpokenTimestamp = -100.0
        lastCaptureStartedTimestamp = -100.0
        lastCaptureEndedTimestamp = -100.0
        isCapturingPhoto = false
        currentHintRepeatCount = 0
        lastSpokenTimeByKey.removeAll()
        lastSpokenText = nil
        lastDecision = nil
        totalSpokenCount = 0
        totalSuppressedCount = 0
    }

    // MARK: - Evaluation & Speech Trigger

    /// Evaluates incoming ComposeOutput against speech suppression rules, triggering audio if unblocked.
    @discardableResult
    public func evaluateAndSpeak(
        output: ComposeOutput,
        isCapturingPhoto: Bool? = nil,
        timestamp: Double? = nil
    ) -> VoicePromptDecision {
        if let capturing = isCapturingPhoto {
            self.isCapturingPhoto = capturing
        }
        let now = timestamp ?? CFAbsoluteTimeGetCurrent()

        // 1. Check mute toggle
        guard isEnabled else {
            return recordDecision(.suppressed(.muted))
        }

        // 2. Defer to VoiceOver if active
        #if canImport(UIKit)
        if UIAccessibility.isVoiceOverRunning {
            return recordDecision(.suppressed(.voiceOverActive))
        }
        #endif

        // 3. Shutter quiet window protection
        if self.isCapturingPhoto ||
            (now - lastCaptureStartedTimestamp) < config.captureQuietWindowSec ||
            (now - lastCaptureEndedTimestamp) < config.captureQuietWindowSec {
            return recordDecision(.suppressed(.shutterQuietWindow))
        }

        // Resolve hint key & spoken text
        let hintKey = output.hintKey ?? (output.isGoodToShoot ? "good" : "")
        let spokenText = resolveSpokenText(from: output, key: hintKey)
        let trimmed = spokenText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return recordDecision(.suppressed(.emptyHint))
        }

        // 4. Good-to-shoot handling and deduplication (no consecutive "good")
        let isGood = output.isGoodToShoot || hintKey == "good"
        if isGood {
            guard config.speakGood else {
                return recordDecision(.suppressed(.muted))
            }
            if lastSpokenRecord?.hintKey == "good" {
                return recordDecision(.suppressed(.duplicateGood))
            }
        }

        // 5. Same-hint deduplication and repeat throttling
        let isSameHint = (hintKey == lastSpokenRecord?.hintKey)
        if isSameHint {
            let elapsedSinceSame = now - (lastSpokenRecord?.timestamp ?? 0.0)
            if currentHintRepeatCount >= config.maxRepeats {
                return recordDecision(.suppressed(.maxRepeatsReached))
            }
            let requiredCooldown = max(config.repeatAfterSec, config.sameHintCooldownSec)
            if elapsedSinceSame < requiredCooldown {
                return recordDecision(.suppressed(.sameHintCooldown))
            }
        } else {
            // Check if this specific hint was recently spoken in history
            if let prevTime = lastSpokenTimeByKey[hintKey], (now - prevTime) < config.sameHintCooldownSec {
                return recordDecision(.suppressed(.sameHintCooldown))
            }
        }

        // 6. Global minimum interval & critical severity priority interruption
        let elapsedGlobal = now - lastSpokenTimestamp
        let isCritical = (output.severity == .critical)

        if elapsedGlobal < config.minIntervalSec {
            if isCritical {
                // Preemptively interrupt lower priority speech
                stopSpeakingImmediate()
                return executeUtterance(
                    text: trimmed,
                    hintKey: hintKey,
                    timestamp: now,
                    isSameHint: isSameHint,
                    isInterrupted: true
                )
            } else {
                return recordDecision(.suppressed(.minIntervalCooldown))
            }
        }

        return executeUtterance(
            text: trimmed,
            hintKey: hintKey,
            timestamp: now,
            isSameHint: isSameHint,
            isInterrupted: false
        )
    }

    // MARK: - Internal Helpers

    private func resolveSpokenText(from output: ComposeOutput, key: String) -> String {
        if let directSpoken = output.hint?.spoken, !directSpoken.isEmpty {
            return directSpoken
        }
        let isEn = config.languageCode.lowercased().starts(with: "en")
        let table = isEn ? Self.englishSpokenTable : Self.chineseSpokenTable
        if let mapped = table[key], !mapped.isEmpty {
            return mapped
        }
        if let fallback = output.hintText, !fallback.isEmpty {
            return fallback
        }
        return ""
    }

    /// Configures AVAudioSession with background mixing and ducking for reliable playback on iOS.
    public func configureAudioSessionIfNeeded() {
        #if os(iOS) && (canImport(AVFAudio) || canImport(AVFoundation))
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.mixWithOthers, .duckOthers, .defaultToSpeaker, .allowBluetoothA2DP]
            )
            try session.setActive(true, options: [])
        } catch {
            // Non-fatal: continue with default audio routing
        }
        #endif
    }

    private func executeUtterance(
        text: String,
        hintKey: String,
        timestamp: Double,
        isSameHint: Bool,
        isInterrupted: Bool
    ) -> VoicePromptDecision {
        if isSameHint {
            currentHintRepeatCount += 1
        } else {
            currentHintRepeatCount = 0
        }

        lastSpokenTimestamp = timestamp
        lastSpokenTimeByKey[hintKey] = timestamp
        lastSpokenText = text

        let record = VoiceUtteranceRecord(
            text: text,
            hintKey: hintKey,
            timestamp: timestamp,
            repeatCount: currentHintRepeatCount,
            isInterrupted: isInterrupted
        )
        lastSpokenRecord = record
        totalSpokenCount += 1

        #if canImport(AVFAudio) || canImport(AVFoundation)
        configureAudioSessionIfNeeded()
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = config.rate
        utterance.volume = config.volume
        utterance.voice = AVSpeechSynthesisVoice(language: config.languageCode)
        synthesizer.speak(utterance)
        #endif

        let decision: VoicePromptDecision = isInterrupted ? .spokenInterrupted(text) : .spoken(text)
        self.lastDecision = decision
        return decision
    }

    private func recordDecision(_ decision: VoicePromptDecision) -> VoicePromptDecision {
        self.lastDecision = decision
        self.totalSuppressedCount += 1
        return decision
    }
}
