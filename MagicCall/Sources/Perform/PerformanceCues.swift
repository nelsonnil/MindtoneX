import AudioToolbox
import CoreHaptics
import SwiftUI
import UIKit

/// Performer-only cues shared by every song input (Manual, AI Voice, Notes, API) and both
/// performance modes: a vibration when the song locks and a small dot in the stage corner.
enum PerformanceCues {
    enum Key {
        static let vibrateOnLock = "cues.vibrateOnSongLock"
        static let dotEnabled = "cues.statusDot.enabled"
        static let dotSize = "cues.statusDot.size"
        static let dotColor = "cues.statusDot.color"
    }

    /// Gap between the two long buzzes when a song locks (performer cue).
    private static let songLockBuzzGap: TimeInterval = 0.55
    private static let songLockBuzzDuration: TimeInterval = 0.38

    static let defaultDotSize = 10.0
    static let dotSizeRange: ClosedRange<Double> = 4...24
    static let defaultDotColor = "#34C759FF"

    struct ColorPreset: Identifiable {
        let name: String
        let hex: String
        var id: String { hex }
    }

    static let colorPresets: [ColorPreset] = [
        ColorPreset(name: "Green", hex: "#34C759FF"),
        ColorPreset(name: "Red", hex: "#FF3B30FF"),
        ColorPreset(name: "Gold", hex: "#E8BA05FF"),
        ColorPreset(name: "White", hex: "#FFFFFFFF"),
        ColorPreset(name: "Gray", hex: "#8E8E93FF"),
        ColorPreset(name: "Black", hex: "#000000FF"),
    ]

    private static var d: UserDefaults { .standard }

    static var vibrateOnLock: Bool { d.object(forKey: Key.vibrateOnLock) == nil ? true : d.bool(forKey: Key.vibrateOnLock) }

    /// The performer's song is locked (AI Voice, API) or loaded from the note (Notes).
    @MainActor
    static func songLocked(source: String) {
        if AppModel.shared.isArmed {
            let track = AppModel.shared.selected ?? AppModel.shared.lastReadyTrack
            if let track {
                PerformUserLog.shared.log("Song ready · “\(track.title) — \(track.artist)”")
            } else {
                PerformUserLog.shared.log("Song ready · \(source)")
            }
        }
        guard vibrateOnLock else { return }
        playSongLockVibration()
        dlog("[CUE] vibration (2× long buzz) · \(source)")
    }

    /// Word API locked — three short taps (distinct from song lock).
    @MainActor
    static func wordLocked(source: String, label: String? = nil) {
        if AppModel.shared.isArmed {
            if let label, !label.isEmpty {
                PerformUserLog.shared.log("Spectator word · “\(label)”")
            } else {
                PerformUserLog.shared.log("Word locked · \(source)")
            }
        }
        guard vibrateOnLock else { return }
        playWordLockVibration()
        dlog("[CUE] vibration (3× short tap) · \(source)")
    }

    private static let wordLockTapDuration: TimeInterval = 0.12
    private static let wordLockTapGap: TimeInterval = 0.14

    @MainActor
    static func playWordLockVibration() {
        playShortTap(repeatCount: 3, gap: wordLockTapGap)
    }

    @MainActor
    private static func playShortTap(repeatCount: Int, gap: TimeInterval) {
        guard repeatCount > 0 else { return }
        playOneShortTap()
        if repeatCount > 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + wordLockTapDuration + gap) {
                playShortTap(repeatCount: repeatCount - 1, gap: gap)
            }
        }
    }

    @MainActor
    private static func playOneShortTap() {
        if playContinuousHapticBuzz(duration: wordLockTapDuration) { return }
        AudioServicesPlaySystemSound(1519)
    }

    private static let candidateBuzzDuration: TimeInterval = 0.45
    private static let failedShortBuzz: TimeInterval = 0.12
    private static let failedGap: TimeInterval = 0.18

    /// Light pulse while frames are collected (scan in progress).
    @MainActor
    static func cardScanningPulse() {
        guard vibrateOnLock else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.65)
        dlog("[CUE] card scanning pulse")
    }

    /// OCR matched a song title (first performer cue during Card scan).
    @MainActor
    static func cardSongRecognized() {
        guard vibrateOnLock else { return }
        playOneLongBuzz(duration: 0.26, sharpness: 0.55)
        dlog("[CUE] card song recognized (1× medium buzz)")
    }

    /// Preview loaded and ready after Card OCR (strong cue — same as song lock).
    @MainActor
    static func cardSongReady() {
        guard vibrateOnLock else { return }
        playSongLockVibration()
        dlog("[CUE] card song ready (2× long buzz)")
    }

    /// Single long buzz — song loaded but needs volume confirm (handwriting uncertain).
    @MainActor
    static func cardCandidateUncertain() {
        guard vibrateOnLock else { return }
        playOneLongBuzz(duration: candidateBuzzDuration, sharpness: 0.45)
        dlog("[CUE] card candidate (1× long buzz)")
    }

    /// Two short buzzes — OCR could not read reliably.
    @MainActor
    static func cardScanFailed() {
        guard vibrateOnLock else { return }
        playOneLongBuzz(duration: failedShortBuzz, sharpness: 0.85)
        DispatchQueue.main.asyncAfter(deadline: .now() + failedShortBuzz + failedGap) {
            playOneLongBuzz(duration: failedShortBuzz, sharpness: 0.85)
        }
        dlog("[CUE] card scan failed (2× short buzz)")
    }

    /// Fixed performer cue: two long buzzes with a clear gap (no pattern picker).
    @MainActor
    static func playSongLockVibration() {
        playOneLongBuzz()
        DispatchQueue.main.asyncAfter(deadline: .now() + songLockBuzzDuration + songLockBuzzGap) {
            playOneLongBuzz()
        }
    }

    @MainActor
    private static func playOneLongBuzz(duration: TimeInterval = songLockBuzzDuration, sharpness: Float = 0.25) {
        if playContinuousHapticBuzz(duration: duration, sharpness: sharpness) { return }
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }

    /// Core Haptics continuous buzz when hardware supports it; otherwise caller uses legacy vibrate.
    @MainActor
    private static func playContinuousHapticBuzz(duration: TimeInterval, sharpness: Float = 0.25) -> Bool {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return false }
        do {
            let engine = try CHHapticEngine()
            try engine.start()
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1)
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [intensity, sharpness],
                relativeTime: 0,
                duration: duration
            )
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) { engine.stop(completionHandler: nil) }
            return true
        } catch {
            dlog("[CUE] Core Haptics buzz failed: \(error.localizedDescription)")
            return false
        }
    }
}

// MARK: Stage dots

/// Song status dot top-trailing on the stage overlay.
struct PerformStageStatusDots: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var voice = VoiceSongSession.shared
    @ObservedObject private var api = ApiSongSession.shared
    @ObservedObject private var card = CardSongSession.shared
    @AppStorage(PerformanceCues.Key.dotEnabled) private var songDotEnabled = false
    @AppStorage(PerformanceCues.Key.dotSize) private var songDotSize = PerformanceCues.defaultDotSize
    @AppStorage(PerformanceCues.Key.dotColor) private var songColorHex = PerformanceCues.defaultDotColor
    @AppStorage(VoiceSettings.Key.inputMode) private var inputModeRaw = VoiceSettings.InputMode.manual.rawValue

    private var songReady: Bool {
        guard model.isArmed, model.loadState == .ready, model.selected != nil else { return false }
        switch VoiceSettings.InputMode(rawValue: inputModeRaw) ?? .manual {
        case .aiVoice: return voice.state == .locked
        case .api: return api.state == .locked
        case .card: return card.state == .locked
        case .notes, .manual: return true
        }
    }

    var body: some View {
        StageCueDot(visible: songDotEnabled && songReady, size: songDotSize, colorHex: songColorHex)
        .padding(.top, 8)
        .padding(.trailing, 12)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .zIndex(999)
    }
}

/// Back-compat name used by `StageView`.
typealias PerformStatusDot = PerformStageStatusDots

private struct StageCueDot: View {
    let visible: Bool
    let size: Double
    let colorHex: String

    var body: some View {
        Circle()
            .fill(Color(hex: colorHex) ?? .green)
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.55), radius: 2, x: 0, y: 1)
            .opacity(visible ? 1 : 0)
            .animation(.easeInOut(duration: 0.25), value: visible)
    }
}

// MARK: Main-screen card

/// Vibration + stage status dot — discrete cues when the song is ready during Perform.
/// Single home card: vibration + stage status dot (replaces separate StatusDot / Vibration cards).
struct FeedbackCard: View {
    @AppStorage(PerformanceCues.Key.vibrateOnLock) private var vibrateOnLock = true
    @AppStorage(PerformanceCues.Key.dotEnabled) private var dotEnabled = false
    @AppStorage(PerformanceCues.Key.dotSize) private var dotSize = PerformanceCues.defaultDotSize
    @AppStorage(PerformanceCues.Key.dotColor) private var colorHex = PerformanceCues.defaultDotColor
    private var dotColor: Binding<Color> {
        Binding(get: { Color(hex: colorHex) ?? .green },
                set: { colorHex = $0.hexString })
    }

    private var summary: String {
        let vib = vibrateOnLock ? "Vibration on" : "Vibration off"
        let song = dotEnabled ? "Song dot on" : "Song dot off"
        return "\(vib) · \(song)"
    }

    var body: some View {
        CollapsibleHomeSection(
            expandedKey: HomeSectionExpandKey.feedback,
            accent: OracleHomeSection.feedback.accent,
            icon: "hand.tap.fill",
            title: "Feedback",
            summary: summary
        ) {
            VStack(alignment: .leading, spacing: 12) {
                feedbackInset {
                    vibrationRow
                }

                feedbackInset {
                    VStack(spacing: 0) {
                        statusDotRow
                        if dotEnabled {
                            CueDivider()
                            dotCustomizeRow(color: dotColor, size: $dotSize, colorHex: $colorHex)
                        }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: dotEnabled)
        }
    }

    private var vibrationRow: some View {
        HStack(spacing: 12) {
            feedbackIcon("iphone.radiowaves.left.and.right")
            VStack(alignment: .leading, spacing: 2) {
                Text("Vibration when song locks")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(OracleTheme.textPrimary)
                Text("Two long buzzes · fixed pattern")
                    .font(.caption2)
                    .foregroundStyle(OracleTheme.textSecondary)
            }
            Spacer(minLength: 4)
            if vibrateOnLock {
                Button {
                    PerformanceCues.playSongLockVibration()
                } label: {
                    Image(systemName: "waveform")
                        .font(.body.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(OracleTheme.gold)
                .accessibilityLabel("Test vibration")
            }
            Toggle("", isOn: $vibrateOnLock)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(OracleTheme.gold)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var statusDotRow: some View {
        HStack(spacing: 12) {
            feedbackIcon("circle.inset.filled")
            VStack(alignment: .leading, spacing: 2) {
                Text("Status dot when song ready")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(OracleTheme.textPrimary)
                Text("Top corner on stage")
                    .font(.caption2)
                    .foregroundStyle(OracleTheme.textSecondary)
            }
            Spacer(minLength: 4)
            Toggle("", isOn: $dotEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(OracleTheme.gold)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func dotCustomizeRow(color: Binding<Color>, size: Binding<Double>, colorHex: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Size \(Int(size.wrappedValue)) pt")
                    .font(.caption)
                    .foregroundStyle(OracleTheme.textSecondary)
                Spacer()
                Circle()
                    .fill(color.wrappedValue)
                    .frame(width: min(size.wrappedValue, 14), height: min(size.wrappedValue, 14))
                Stepper("", value: size, in: PerformanceCues.dotSizeRange, step: 1)
                    .labelsHidden()
                    .tint(OracleTheme.gold)
            }
            HStack(spacing: 8) {
                ColorPicker("", selection: color, supportsOpacity: true)
                    .labelsHidden()
                    .frame(width: 28, height: 28)
                ForEach(PerformanceCues.colorPresets) { preset in
                    presetSwatch(preset, selectedHex: colorHex.wrappedValue) { colorHex.wrappedValue = $0 }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func feedbackIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.body.weight(.semibold))
            .foregroundStyle(OracleHomeSection.feedback.accent)
            .frame(width: 36, height: 36)
            .background(OracleHomeSection.feedback.accent.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func feedbackInset<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
            }
    }

    private func presetSwatch(_ preset: PerformanceCues.ColorPreset, selectedHex: String, onSelect: @escaping (String) -> Void) -> some View {
        let selected = selectedHex.uppercased() == preset.hex
        return Button {
            onSelect(preset.hex)
        } label: {
            Circle()
                .fill(Color(hex: preset.hex) ?? .clear)
                .frame(width: 22, height: 22)
                .overlay { Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5) }
                .overlay { Circle().strokeBorder(OracleTheme.gold, lineWidth: selected ? 2 : 0).padding(-2) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.name)
    }
}

private struct CueDivider: View {
    var body: some View {
        Divider().overlay(OracleTheme.cardBorder).padding(.leading, 14)
    }
}

// MARK: Hex colors

extension Color {
    /// `#RRGGBB` or `#RRGGBBAA`.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let value = UInt64(s, radix: 16) else { return nil }
        let rgba = s.count == 6 ? (value << 8) | 0xFF : value
        self.init(.sRGB,
                  red: Double((rgba >> 24) & 0xFF) / 255,
                  green: Double((rgba >> 16) & 0xFF) / 255,
                  blue: Double((rgba >> 8) & 0xFF) / 255,
                  opacity: Double(rgba & 0xFF) / 255)
    }

    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X%02X", byte(r), byte(g), byte(b), byte(a))
    }
}
