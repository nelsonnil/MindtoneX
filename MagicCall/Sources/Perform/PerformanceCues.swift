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

    static let defaultDotSize = 8.0
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
        guard vibrateOnLock else { return }
        playSongLockVibration()
        dlog("[CUE] vibration (2× long buzz) · \(source)")
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
    private static func playOneLongBuzz() {
        if playContinuousHapticBuzz(duration: songLockBuzzDuration) { return }
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }

    /// Core Haptics continuous buzz when hardware supports it; otherwise caller uses legacy vibrate.
    @MainActor
    private static func playContinuousHapticBuzz(duration: TimeInterval) -> Bool {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return false }
        do {
            let engine = try CHHapticEngine()
            try engine.start()
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1)
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.25)
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

// MARK: Dot

/// Small dot in the top-right corner of the stage (black stage or Notes) for the performer.
struct PerformStatusDot: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var voice = VoiceSongSession.shared
    @ObservedObject private var api = ApiSongSession.shared
    @AppStorage(PerformanceCues.Key.dotEnabled) private var enabled = false
    @AppStorage(PerformanceCues.Key.dotSize) private var size = PerformanceCues.defaultDotSize
    @AppStorage(PerformanceCues.Key.dotColor) private var colorHex = PerformanceCues.defaultDotColor
    @AppStorage(VoiceSettings.Key.inputMode) private var inputModeRaw = VoiceSettings.InputMode.manual.rawValue

    private var songReady: Bool {
        guard model.loadState == .ready, model.selected != nil else { return false }
        switch VoiceSettings.InputMode(rawValue: inputModeRaw) ?? .manual {
        case .aiVoice: return voice.state == .locked
        case .api: return api.state == .locked
        case .notes, .manual: return true
        }
    }

    private var visible: Bool {
        enabled && songReady
    }

    var body: some View {
        Circle()
            .fill(Color(hex: colorHex) ?? .green)
            .frame(width: size, height: size)
            .opacity(visible ? 1 : 0)
            .padding(.top, 4)
            .padding(.trailing, 10)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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
    @AppStorage("ui.feedbackExpanded") private var expanded = false

    private var dotColor: Binding<Color> {
        Binding(get: { Color(hex: colorHex) ?? .green },
                set: { colorHex = $0.hexString })
    }

    private var summary: String {
        let vib = vibrateOnLock ? "Vibration on" : "Vibration off"
        let dot = dotEnabled ? "Status dot on" : "Status dot off"
        return "\(vib) · \(dot)"
    }

    var body: some View {
        HomePanel(padding: 0, accent: OracleHomeSection.feedback.accent) {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 12) {
                    feedbackInset {
                        vibrationRow
                    }

                    feedbackInset {
                        VStack(spacing: 0) {
                            statusDotRow
                            if dotEnabled {
                                CueDivider()
                                dotCustomizeRow
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
                .animation(.easeInOut(duration: 0.2), value: dotEnabled)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "hand.tap.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(OracleHomeSection.feedback.accent)
                        .frame(width: 40, height: 40)
                        .background(OracleHomeSection.feedback.accent.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Feedback")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(OracleTheme.textPrimary)
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(OracleTheme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(20)
            }
            .tint(OracleTheme.gold)
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
                Text("Top-right on stage · only when loaded")
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

    private var dotCustomizeRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Size \(Int(dotSize)) pt")
                    .font(.caption)
                    .foregroundStyle(OracleTheme.textSecondary)
                Spacer()
                Circle()
                    .fill(dotColor.wrappedValue)
                    .frame(width: min(dotSize, 14), height: min(dotSize, 14))
                Stepper("", value: $dotSize, in: PerformanceCues.dotSizeRange, step: 1)
                    .labelsHidden()
                    .tint(OracleTheme.gold)
            }
            HStack(spacing: 8) {
                ColorPicker("", selection: dotColor, supportsOpacity: true)
                    .labelsHidden()
                    .frame(width: 28, height: 28)
                ForEach(PerformanceCues.colorPresets) { preset in
                    presetSwatch(preset)
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

    private func presetSwatch(_ preset: PerformanceCues.ColorPreset) -> some View {
        let selected = colorHex.uppercased() == preset.hex
        return Button {
            colorHex = preset.hex
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
