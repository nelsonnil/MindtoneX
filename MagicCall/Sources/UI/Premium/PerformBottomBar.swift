import SwiftUI

/// Fixed bottom bar: one always-visible readiness strip above the mode-colored Perform CTA.
struct PerformBottomBar: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(VoiceSettings.Key.inputMode) private var inputModeRaw = VoiceSettings.InputMode.manual.rawValue
    @AppStorage(ApiSettings.Key.provider) private var apiProviderRaw = ApiSettings.Provider.inject.rawValue
    @AppStorage(ApiSettings.Key.injectID) private var injectID = ""
    @AppStorage(ApiSettings.Key.elipsURL) private var elipsURL = ""
    @AppStorage(ApiSettings.Key.customURL) private var customURL = ""
    @AppStorage(ApiSettings.Key.customField) private var customField = ApiSettings.defaultCustomField
    let mode: Prefs.PerformanceMode

    var body: some View {
        VStack(spacing: 10) {
            ReadinessStatusBar(mode: mode)

            OraclePerformButton(
                title: "Perform",
                gradient: OracleTheme.performGradient(for: mode),
                disabled: !model.canPerform,
                emphasizeReady: model.canPerform
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
                OracleTheme.ink.opacity(0.62)
                LinearGradient(
                    colors: [OracleTheme.gold.opacity(model.canPerform ? 0.35 : 0.12), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 3)
                Rectangle()
                    .fill(OracleTheme.cardBorderHighlight)
                    .frame(height: 0.5)
                    .offset(y: 3)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

struct ReadinessStatusBar: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var voice = VoiceSongSession.shared
    @ObservedObject private var api = ApiSongSession.shared
    @AppStorage(VoiceSettings.Key.inputMode) private var inputModeRaw = VoiceSettings.InputMode.manual.rawValue
    @AppStorage(SilentShortcut.Key.silentOnEnabled) private var silentOnEnabled = false
    @AppStorage(ApiSettings.Key.provider) private var apiProviderRaw = ApiSettings.Provider.inject.rawValue
    @AppStorage(ApiSettings.Key.injectID) private var injectID = ""
    @AppStorage(ApiSettings.Key.elipsURL) private var elipsURL = ""
    @AppStorage(ApiSettings.Key.customURL) private var customURL = ""
    @AppStorage(ApiSettings.Key.customField) private var customField = ApiSettings.defaultCustomField
    @AppStorage(SilentShortcut.Key.silentOffEnabled) private var silentOffEnabled = false
    @AppStorage(NotesSettings.Key.idleSearchEnabled) private var idleSearchEnabled = true
    @AppStorage(NotesSettings.Key.idleDelay) private var idleDelay = NotesSettings.defaultIdleDelay
    @AppStorage(NotesSettings.Key.searchOnReturn) private var searchOnReturn = true

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
                return Status(tone: .warning, icon: "link.circle", text: "Voice — paste token under Connection")
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
                return Status(tone: .ready, icon: "mic.circle.fill", text: "Ready · Voice listens on Perform")
            }
        case .api:
            let name = ApiSettings.provider.title
            guard ApiSettings.isConfigured else {
                return Status(tone: .warning, icon: "key.fill", text: "API needs setup — \(ApiSettings.setupHint)")
            }
            if api.isActive, api.isStruggling {
                return Status(tone: .warning, icon: "wifi.exclamationmark", text: "\(name) not reachable — retrying")
            }
            switch api.state {
            case .connecting:
                return Status(tone: .working, icon: "antenna.radiowaves.left.and.right", text: "Connecting to \(name)…")
            case .watching:
                return Status(tone: .working, icon: "dot.radiowaves.left.and.right", text: "Waiting for the spectator’s search…")
            case .loading(let label):
                return Status(tone: .working, icon: "arrow.down.circle", text: "Found “\(label)” · loading…")
            case .locked:
                let title = model.selected.map { "\($0.title) — \($0.artist)" } ?? api.lockedReading?.label ?? "song"
                return Status(tone: .ready, icon: "lock.fill", text: "Locked · \(title)")
            case .failed(let message):
                return Status(tone: .warning, icon: "exclamationmark.triangle.fill", text: message)
            case .idle:
                return Status(tone: .ready, icon: "link.circle.fill", text: "Ready · \(name) picks the song on Perform")
            }
        case .notes:
            let when = [idleSearchEnabled ? "after \(NotesInputControls.format(idleDelay)) idle" : nil,
                        searchOnReturn ? "on Return" : nil].compactMap { $0 }
            let detail = when.isEmpty ? "searches on ✓ or call" : "searches \(when.joined(separator: " / "))"
            return Status(tone: .ready, icon: "note.text", text: "Ready · Notes \(detail)")
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
                Text(mode.shortBadge)
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
