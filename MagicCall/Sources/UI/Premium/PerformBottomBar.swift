import SwiftUI

/// Fixed bottom bar: one always-visible readiness strip above the mode-colored Perform CTA.
struct PerformBottomBar: View {
    @EnvironmentObject private var model: AppModel
    let mode: Prefs.PerformanceMode

    var body: some View {
        VStack(spacing: 10) {
            ReadinessStatusBar(mode: mode)

            OraclePerformButton(
                title: "Perform",
                gradient: OracleTheme.performGradient(for: mode),
                disabled: !model.canPerform
            ) {
                model.perform()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .background {
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                OracleTheme.ink.opacity(0.55)
                Rectangle()
                    .fill(OracleTheme.cardBorderHighlight)
                    .frame(height: 0.5)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

struct ReadinessStatusBar: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var voice = VoiceSongSession.shared
    @AppStorage(VoiceSettings.Key.inputMode) private var inputModeRaw = VoiceSettings.InputMode.manual.rawValue
    @AppStorage(SilentShortcut.Key.silentOnEnabled) private var silentOnEnabled = false
    @AppStorage(SilentShortcut.Key.silentOffEnabled) private var silentOffEnabled = false

    let mode: Prefs.PerformanceMode

    private enum Tone { case idle, working, ready, warning }

    private struct Status {
        let tone: Tone
        let icon: String
        let text: String
    }

    private var inputMode: VoiceSettings.InputMode {
        VoiceSettings.InputMode(rawValue: inputModeRaw) ?? .manual
    }

    private var shortcutOn: Bool { mode == .fakeRingtone ? silentOnEnabled : silentOffEnabled }

    private var status: Status {
        switch inputMode {
        case .manual:
            switch model.loadState {
            case .idle:
                return Status(tone: .idle, icon: "circle.dotted", text: "Search a song to get ready")
            case .searching:
                return Status(tone: .working, icon: "magnifyingglass", text: "Searching…")
            case .downloading:
                return Status(tone: .working, icon: "arrow.down.circle", text: "Downloading preview…")
            case .ready:
                let title = model.selected.map { "\($0.title) — \($0.artist)" } ?? "Song loaded"
                if mode == .shareRingtone, model.ringtoneStaged {
                    return Status(tone: .ready, icon: "checkmark.seal.fill", text: "Ready · ringtone file prepared · \(title)")
                }
                return Status(tone: .ready, icon: "checkmark.circle.fill", text: "Ready · \(title)")
            case .failed:
                return Status(tone: .warning, icon: "exclamationmark.triangle.fill", text: "Search failed — try again")
            }
        case .aiVoice:
            guard VoiceSettings.isConfigured else {
                return Status(tone: .warning, icon: "key.fill", text: "AI Voice needs setup — see Advanced")
            }
            if case .failed(let message) = voice.state {
                return Status(tone: .warning, icon: "exclamationmark.triangle.fill", text: message)
            }
            switch voice.state {
            case .starting:
                return Status(tone: .working, icon: "mic.fill", text: "Starting microphone…")
            case .listening:
                return Status(tone: .working, icon: "waveform", text: "Listening…")
            case .locked:
                let pick = voice.lockedPick?.label ?? "song"
                return Status(tone: .ready, icon: "lock.fill", text: "Locked · \(pick)")
            default:
                return Status(tone: .ready, icon: "mic.circle.fill", text: "Ready · AI Voice picks the song on Perform")
            }
        }
    }

    private func fill(for tone: Tone) -> (color: Color, opacity: Double) {
        switch tone {
        case .idle: return (Color.white, 0.07)
        case .working: return (OracleTheme.indigo, 0.45)
        case .ready: return (OracleTheme.gold, 0.92)
        case .warning: return (OracleTheme.coral, 0.85)
        }
    }

    var body: some View {
        let current = status
        let background = fill(for: current.tone)
        let label = OracleTheme.adaptiveLabel(on: background.color, opacity: background.opacity, over: OracleTheme.ink)

        HStack(spacing: 8) {
            Image(systemName: current.icon)
                .font(.caption.weight(.semibold))
                .symbolEffect(.pulse, isActive: current.tone == .working)
            Text(current.text)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            HStack(spacing: 4) {
                if shortcutOn {
                    Image(systemName: "bolt.fill")
                        .accessibilityLabel("Silent shortcut on")
                }
                Text(mode == .fakeRingtone ? "FAKE" : "SHARE")
                    .tracking(1)
            }
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .opacity(0.75)
        }
        .foregroundStyle(label)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .frame(maxWidth: .infinity)
        .background(background.color.opacity(background.opacity))
        .clipShape(Capsule())
        .overlay {
            Capsule().strokeBorder(Color.white.opacity(current.tone == .idle ? 0.10 : 0.18), lineWidth: 0.5)
        }
        .animation(.easeInOut(duration: 0.2), value: current.text)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(current.text)")
    }
}
