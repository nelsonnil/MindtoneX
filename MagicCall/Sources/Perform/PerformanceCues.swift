import AudioToolbox
import SwiftUI
import UIKit

/// Performer-only cues shared by every song input (Manual, AI Voice, Notes, API) and both
/// performance modes: a vibration when the song locks and a small dot in the stage corner.
enum PerformanceCues {
    enum Key {
        static let vibrateOnLock = "cues.vibrateOnSongLock"
        static let vibrationStyle = "cues.vibrationStyle"
        static let dotEnabled = "cues.statusDot.enabled"
        static let dotSize = "cues.statusDot.size"
        static let dotColor = "cues.statusDot.color"
        static let dotTiming = "cues.statusDot.timing"
    }

    enum VibrationStyle: String, CaseIterable, Identifiable {
        case alert
        case heavyDouble
        case longBuzz

        var id: String { rawValue }
        var title: String {
            switch self {
            case .alert: return "Strong — 3 taps"
            case .heavyDouble: return "Heavy — 2 taps"
            case .longBuzz: return "Long buzz"
            }
        }
    }

    enum DotTiming: String, CaseIterable, Identifiable {
        case songReady
        case always

        var id: String { rawValue }
        var title: String {
            switch self {
            case .songReady: return "When song is ready"
            case .always: return "Always in Perform"
            }
        }
    }

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
    static var vibrationStyle: VibrationStyle {
        VibrationStyle(rawValue: d.string(forKey: Key.vibrationStyle) ?? "") ?? .alert
    }

    /// The performer's song is locked (AI Voice, API) or loaded from the note (Notes).
    @MainActor
    static func songLocked(source: String) {
        guard vibrateOnLock else { return }
        vibrate(vibrationStyle)
        dlog("[CUE] vibration (\(vibrationStyle.rawValue)) · \(source)")
    }

    @MainActor
    static func vibrate(_ style: VibrationStyle) {
        switch style {
        case .alert:
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.error)
        case .heavyDouble:
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.prepare()
            generator.impactOccurred(intensity: 1)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { generator.impactOccurred(intensity: 1) }
        case .longBuzz:
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
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
    @AppStorage(PerformanceCues.Key.dotTiming) private var timingRaw = PerformanceCues.DotTiming.songReady.rawValue
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
        guard enabled else { return false }
        return PerformanceCues.DotTiming(rawValue: timingRaw) == .always || songReady
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
struct PerformanceFeedbackCard: View {
    @AppStorage(PerformanceCues.Key.vibrateOnLock) private var vibrateOnLock = true
    @AppStorage(PerformanceCues.Key.vibrationStyle) private var styleRaw = PerformanceCues.VibrationStyle.alert.rawValue
    @AppStorage(PerformanceCues.Key.dotEnabled) private var dotEnabled = false
    @AppStorage(PerformanceCues.Key.dotSize) private var dotSize = PerformanceCues.defaultDotSize
    @AppStorage(PerformanceCues.Key.dotColor) private var colorHex = PerformanceCues.defaultDotColor
    @AppStorage(PerformanceCues.Key.dotTiming) private var timingRaw = PerformanceCues.DotTiming.songReady.rawValue

    private var dotColor: Binding<Color> {
        Binding(get: { Color(hex: colorHex) ?? .green },
                set: { colorHex = $0.hexString })
    }

    var body: some View {
        OracleCard(section: .feedback) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    OracleEyebrow(text: "Feedback")
                    Text("Quiet cues so you know the song is ready — without looking at the status bar.")
                        .font(.caption)
                        .foregroundStyle(OracleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                vibrationSection
                statusDotSection
            }
            .animation(.easeInOut(duration: 0.2), value: vibrateOnLock)
            .animation(.easeInOut(duration: 0.2), value: dotEnabled)
        }
    }

    private var vibrationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            CueSectionTitle("Vibration")
            CueRows {
                CueRow {
                    Toggle(isOn: $vibrateOnLock) { CueLabel("When song locks") }
                        .toggleStyle(.switch)
                        .tint(OracleTheme.gold)
                }
                if vibrateOnLock {
                    CueDivider()
                    CueRow {
                        HStack {
                            CueLabel("Pattern")
                            Spacer(minLength: 8)
                            Picker("Pattern", selection: $styleRaw) {
                                ForEach(PerformanceCues.VibrationStyle.allCases) { Text($0.title).tag($0.rawValue) }
                            }
                            .labelsHidden()
                            .tint(OracleTheme.gold)
                            Button {
                                PerformanceCues.vibrate(PerformanceCues.VibrationStyle(rawValue: styleRaw) ?? .alert)
                            } label: {
                                Image(systemName: "iphone.radiowaves.left.and.right")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(OracleTheme.gold)
                            .accessibilityLabel("Test vibration")
                        }
                    }
                }
            }
            CueFooter("AI Voice, API, or Notes during Perform. Manual input is already ready before you start.")
        }
    }

    private var statusDotSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            CueSectionTitle("Status dot")
            CueRows {
                CueRow {
                    Toggle(isOn: $dotEnabled) { CueLabel("Show on stage") }
                        .toggleStyle(.switch)
                        .tint(OracleTheme.gold)
                }
                if dotEnabled {
                    CueDivider()
                    CueRow {
                        HStack {
                            CueLabel("Show")
                            Spacer(minLength: 8)
                            Picker("Show", selection: $timingRaw) {
                                ForEach(PerformanceCues.DotTiming.allCases) { Text($0.title).tag($0.rawValue) }
                            }
                            .labelsHidden()
                            .tint(OracleTheme.gold)
                        }
                    }
                    CueDivider()
                    CueRow {
                        HStack {
                            CueLabel("Size \(Int(dotSize)) pt")
                            Spacer(minLength: 8)
                            Circle()
                                .fill(dotColor.wrappedValue)
                                .frame(width: dotSize, height: dotSize)
                                .frame(width: 26)
                            Stepper("", value: $dotSize, in: PerformanceCues.dotSizeRange, step: 1)
                                .labelsHidden()
                                .tint(OracleTheme.gold)
                        }
                    }
                    CueDivider()
                    CueRow {
                        VStack(alignment: .leading, spacing: 10) {
                            ColorPicker(selection: dotColor, supportsOpacity: true) { CueLabel("Color") }
                            HStack(spacing: 10) {
                                ForEach(PerformanceCues.colorPresets) { preset in
                                    presetSwatch(preset)
                                }
                            }
                        }
                    }
                }
            }
            CueFooter("Top-right on the stage (black screen, wallpaper, or Notes). “When song is ready” follows AI Voice / API lock.")
        }
    }

    private func presetSwatch(_ preset: PerformanceCues.ColorPreset) -> some View {
        let selected = colorHex.uppercased() == preset.hex
        return Button {
            colorHex = preset.hex
        } label: {
            Circle()
                .fill(Color(hex: preset.hex) ?? .clear)
                .frame(width: 24, height: 24)
                .overlay { Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5) }
                .overlay { Circle().strokeBorder(OracleTheme.gold, lineWidth: selected ? 2 : 0).padding(-3) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.name)
    }
}

// MARK: Row styling

private struct CueRows<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0, content: content)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
            }
    }
}

private struct CueRow<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
    }
}

private struct CueDivider: View {
    var body: some View {
        Divider().overlay(OracleTheme.cardBorder).padding(.leading, 14)
    }
}

private struct CueSectionTitle: View {
    let text: String
    @Environment(\.oracleSectionAccent) private var sectionAccent
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle((sectionAccent ?? OracleTheme.textSecondary).opacity(0.88))
            .tracking(0.6)
    }
}

private struct CueLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(OracleTheme.textPrimary)
    }
}

private struct CueFooter: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(OracleTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
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
