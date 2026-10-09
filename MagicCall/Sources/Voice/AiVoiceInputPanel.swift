import SwiftUI

/// Single home-screen surface for AI Voice: language, locking, and live listen debug (API key → Performance settings).
struct AiVoiceInputPanel: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var voice = VoiceSongSession.shared

    @AppStorage(VoiceSettings.Key.language) private var languageRaw = "en"
    @AppStorage(SpectatorSettings.Key.count) private var spectatorCount = 1

    private var configured: Bool { VoiceSettings.isConfigured }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            connectionBlock
            VoiceLockingControls()
            liveListenBlock
        }
        .onAppear {
            if languageRaw == "es-en" { languageRaw = "es" }
        }
    }

    // MARK: Connection & key

    private var selectedLanguage: VoiceOpenAILanguages.Option {
        VoiceOpenAILanguages.resolve(stored: languageRaw)
    }

    private var showsVoiceOpenAIHints: Bool {
        !model.isPerformTrickUIActive
    }

    private var connectionBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            OracleEyebrow(text: "Voice language")
            if showsVoiceOpenAIHints {
                Text(OpenAIAPIKeyCopy.performanceSettingsHint)
                    .font(.caption)
                    .foregroundStyle(OracleTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let onFile = VoiceSettings.apiKeyOnFileLabel {
                    Label(onFile, systemImage: "key.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(OracleTheme.gold.opacity(0.95))
                }
            }

            VStack(spacing: 0) {
                languageMenuRow
            }
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
            }
        }
    }

    private var languageMenuRow: some View {
        Menu {
            ForEach(VoiceOpenAILanguages.homeMenuOptions) { option in
                Button {
                    languageRaw = option.id
                } label: {
                    if option.id == languageRaw {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text("Language")
                    .font(.subheadline)
                    .foregroundStyle(OracleTheme.textPrimary)
                Spacer(minLength: 8)
                Text(selectedLanguage.title)
                    .font(.subheadline)
                    .foregroundStyle(OracleTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(OracleTheme.textSecondary.opacity(0.8))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .tint(OracleTheme.textPrimary)
    }

    // MARK: Live listen (debug)

    private var liveListenBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                OracleEyebrow(text: "Live preview")
                Spacer()
                voiceStatusChip
            }
            Text("Talk like on stage. You’ll see what the app hears and which song it picks. Nothing is shown during Perform.")
                .font(.caption)
                .foregroundStyle(OracleTheme.textSecondary)

            livePreviewTestControls

            if showsVoiceOpenAIHints, !configured {
                Label("Add your OpenAI API key under Performance settings to enable voice tests.", systemImage: "link.circle")
                    .font(.caption)
                    .foregroundStyle(OracleTheme.coral)
            }

            if voice.isActive {
                LevelMeter(level: voice.level)
            }

            if case .failed(let message) = voice.state {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(OracleTheme.coral)
            }

            transcriptBox
            pickBox
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
        }
    }

    private var livePreviewTestControls: some View {
        VStack(spacing: 10) {
            if voice.isActive {
                Button { voice.stopTest() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "stop.circle.fill")
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Stop listening")
                                .font(.subheadline.weight(.bold))
                            Text("End this test run")
                                .font(.caption2)
                                .opacity(0.85)
                        }
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.red.opacity(0.88))
                    )
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    model.clearSongForNextPerformance()
                    Task { await voice.start(context: .test) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "mic.circle.fill")
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Test voice")
                                .font(.subheadline.weight(.bold))
                            Text("Speak a song title like on stage")
                                .font(.caption2)
                                .opacity(0.9)
                        }
                        Spacer()
                        Image(systemName: "waveform")
                            .font(.body.weight(.semibold))
                            .opacity(configured ? 1 : 0.35)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: configured
                                        ? [OracleTheme.gold, OracleTheme.gold.opacity(0.72)]
                                        : [Color.gray.opacity(0.35), Color.gray.opacity(0.25)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
                .buttonStyle(.plain)
                .disabled(!configured)
            }

            if voice.hasContent && !voice.isActive {
                Button {
                    model.resetVoicePerformance()
                    SecondSpectatorSong.shared.reset(reason: "voice test cleared")
                } label: {
                    Label("Clear transcript & pick", systemImage: "arrow.counterclockwise")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(OracleTheme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var voiceStatusChip: some View {
        let (text, color): (String, Color) = {
            switch voice.state {
            case .idle: return ("Off", OracleTheme.textSecondary)
            case .starting: return ("Preparing voice…", OracleTheme.indigo)
            case .listening: return (voice.listeningForSecondSong ? "Listening · song 2" : "Listening", OracleTheme.coral)
            case .locked: return ("Locked", OracleTheme.gold)
            case .failed: return ("Error", OracleTheme.coral)
            }
        }()
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    private var transcriptBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What it heard")
                .font(.caption.weight(.semibold))
                .foregroundStyle(OracleTheme.textSecondary)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        if voice.lines.isEmpty {
                            Text(voice.isActive ? "Listening… say something." : "Nothing yet. Tap Test and talk.")
                                .foregroundStyle(OracleTheme.textSecondary.opacity(0.7))
                        }
                        ForEach(voice.lines) { line in
                            Text(line.text.isEmpty ? "…" : line.text)
                                .foregroundStyle(line.isFinal ? OracleTheme.textPrimary : OracleTheme.textSecondary)
                                .italic(!line.isFinal)
                                .id(line.id)
                        }
                    }
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                }
                .frame(minHeight: 60, maxHeight: 140)
                .onChange(of: voice.lines) { _, lines in
                    if let last = lines.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .padding(10)
            .background(Color.black.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var pickBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Test")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OracleTheme.textSecondary)
                if voice.isThinking {
                    ProgressView().controlSize(.mini)
                    Text("Matching…").font(.caption2).foregroundStyle(OracleTheme.textSecondary)
                }
            }
            if spectatorCount == 2 {
                VStack(alignment: .leading, spacing: 8) {
                    spectatorPickRow(1, pick: voice.lockedPick ?? voice.candidate, status: firstSpectatorStatus)
                    spectatorPickRow(2, pick: voice.secondLockedPick ?? voice.secondCandidate, status: secondSpectatorStatus)
                }
            } else if let pick = voice.lockedPick ?? voice.candidate {
                VStack(alignment: .leading, spacing: 4) {
                    Text(pick.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(OracleTheme.textPrimary)
                    Text("Confidence \(VoiceSongSession.percent(pick.confidence))")
                        .font(.caption)
                        .foregroundStyle(OracleTheme.textSecondary)
                    pickStatus
                }
            } else {
                Text("No song yet.")
                    .font(.footnote)
                    .foregroundStyle(OracleTheme.textSecondary.opacity(0.7))
            }
            if let error = voice.lastAIError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(OracleTheme.coral)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.black.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Two spectators

    private func spectatorPickRow(_ number: Int, pick: SongPick?, status: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(OracleTheme.ink)
                .frame(width: 18, height: 18)
                .background(OracleTheme.gold.opacity(pick == nil ? 0.35 : 1), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(pick?.label ?? "No song yet")
                    .font(.subheadline.weight(pick == nil ? .regular : .semibold))
                    .foregroundStyle(pick == nil ? OracleTheme.textSecondary : OracleTheme.textPrimary)
                    .lineLimit(1)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(OracleTheme.textSecondary)
            }
        }
    }

    private var firstSpectatorStatus: String {
        if voice.lockedPick != nil { return "Locked" }
        return prepStatus(voice.prep) ?? (voice.isActive ? "Listening for spectator 1…" : "Spectator 1")
    }

    private var secondSpectatorStatus: String {
        if voice.secondLockedPick != nil { return "Locked — listening stopped" }
        if voice.listeningForSecondSong {
            return prepStatus(voice.secondPrep) ?? "Listening for spectator 2…"
        }
        return voice.lockedPick == nil ? "Starts after song 1 locks" : "Not locked"
    }

    private func prepStatus(_ prep: VoiceSongSession.Prep?) -> String? {
        switch prep {
        case .preparing: return "Finding and preparing the song…"
        case .ready: return "Ready · locks after \(Int(VoiceSettings.lockDelay)) s without changes"
        case .notFound: return "Not found in previews — keep speaking"
        case nil: return nil
        }
    }

    @ViewBuilder
    private var pickStatus: some View {
        if voice.state == .locked {
            Label("Locked — listening stopped", systemImage: "lock.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(OracleTheme.gold)
        } else {
            switch voice.prep {
            case .preparing:
                Label("Finding and preparing the song…", systemImage: "arrow.down.circle")
                    .font(.caption)
                    .foregroundStyle(OracleTheme.textSecondary)
            case .notFound:
                Label("Not found in previews — keep speaking or try again", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(OracleTheme.coral)
            case .ready:
                if let deadline = voice.lockDeadline {
                    TimelineView(.periodic(from: .now, by: 0.25)) { context in
                        let left = max(0, Int(deadline.timeIntervalSince(context.date).rounded(.up)))
                        Label("Ready · locks in \(left) s unless they change their mind", systemImage: "timer")
                            .font(.caption)
                            .foregroundStyle(OracleTheme.indigo)
                    }
                } else {
                    Label("Ready", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(OracleTheme.textSecondary)
                }
            case nil:
                EmptyView()
            }
        }
    }

}
