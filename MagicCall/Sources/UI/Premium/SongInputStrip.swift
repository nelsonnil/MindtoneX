import SwiftUI

struct SongInputStrip: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var voice = VoiceSongSession.shared
    @Binding var inputModeRaw: String
    @FocusState.Binding var queryFocused: Bool

    @State private var showVoiceDebug = false

    private var inputMode: VoiceSettings.InputMode {
        VoiceSettings.InputMode(rawValue: inputModeRaw) ?? .manual
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    inputChip("Manual", icon: "keyboard", mode: .manual)
                    inputChip("AI Voice", icon: "mic.fill", mode: .aiVoice)
                    disabledChip("API", subtitle: "Soon")
                }
            }

            Group {
                switch inputMode {
                case .manual:
                    manualField
                case .aiVoice:
                    aiVoiceCompact
                }
            }

            Text(statusLine)
                .font(.caption)
                .foregroundStyle(OracleTheme.textSecondary)
                .lineLimit(2)
        }
        .sheet(isPresented: $showVoiceDebug) {
            NavigationStack {
                VoiceDebugSheet()
            }
            .presentationDetents([.large])
        }
    }

    private func inputChip(_ title: String, icon: String, mode: VoiceSettings.InputMode) -> some View {
        let selected = inputMode == mode
        return Button {
            VoiceSongSession.shared.stopTest()
            withAnimation(.easeInOut(duration: 0.2)) { inputModeRaw = mode.rawValue }
            dlog("Song input → \(mode.title)")
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if mode == .aiVoice, voice.isActive {
                    Circle().fill(Color.red).frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .foregroundStyle(selected ? OracleTheme.textPrimary : OracleTheme.textSecondary)
            .background(selected ? OracleTheme.indigo.opacity(0.25) : Color.white.opacity(0.04))
            .overlay {
                Capsule().stroke(selected ? OracleTheme.gold.opacity(0.6) : OracleTheme.cardBorder, lineWidth: 1)
            }
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.6).onEnded { _ in
                if mode == .aiVoice { showVoiceDebug = true }
            }
        )
    }

    private func disabledChip(_ title: String, subtitle: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "link")
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(subtitle)
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .foregroundStyle(OracleTheme.textSecondary.opacity(0.5))
        .overlay { Capsule().stroke(OracleTheme.cardBorder, lineWidth: 1) }
    }

    private var manualField: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("Song title & artist", text: $model.query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($queryFocused)
                    .onSubmit { Task { await model.search() } }
                    .padding(12)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button {
                    queryFocused = false
                    Task { await model.search() }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(OracleTheme.goldGradient)
                        .foregroundStyle(Color(red: 0.12, green: 0.10, blue: 0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(model.query.trimmingCharacters(in: .whitespaces).isEmpty || model.loadState == .searching)
            }

            if let track = model.selected, model.loadState == .ready {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(OracleTheme.gold)
                    Text("\(track.title) — \(track.artist)")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button {
                        model.audition()
                    } label: {
                        Image(systemName: model.isAudible ? "speaker.wave.2.fill" : "play.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(OracleTheme.gold)
                    .disabled(model.isAudible)
                }
                .padding(10)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if case .failed(let message) = model.loadState {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(OracleTheme.coral)
            }
        }
    }

    private var aiVoiceCompact: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !VoiceSettings.isConfigured {
                Label("Add API key in Guide → Voice settings", systemImage: "key.fill")
                    .font(.caption)
                    .foregroundStyle(OracleTheme.coral)
            }

            HStack(spacing: 10) {
                if voice.isActive {
                    Button(role: .destructive) { voice.stopTest() } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        model.clearSongForNextPerformance()
                        Task { await voice.start(context: .test) }
                    } label: {
                        Label("Listen test", systemImage: "mic.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(OracleTheme.indigo)
                    .disabled(!VoiceSettings.isConfigured)
                }
                Button("Voice debug") { showVoiceDebug = true }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OracleTheme.textSecondary)
            }

            if voice.isActive {
                LevelMeter(level: voice.level)
            }

            if let pick = voice.lockedPick ?? voice.candidate {
                Text(pick.label)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
            }
        }
    }

    private var statusLine: String {
        switch inputMode {
        case .manual:
            switch model.loadState {
            case .idle: return "Search for a song to begin."
            case .searching: return "Searching…"
            case .downloading: return "Downloading preview…"
            case .ready:
                if let track = model.selected {
                    return "Ready · \(track.title)"
                }
                return "Ready"
            case .failed: return "Search failed — try again."
            }
        case .aiVoice:
            switch voice.state {
            case .idle: return VoiceSettings.isConfigured ? "Tap Listen test to try AI Voice." : "Need API key or Apple on-device engine."
            case .starting: return "Starting microphone…"
            case .listening: return "Listening…"
            case .locked: return "Locked · song ready for Perform"
            case .failed(let m): return m
            }
        }
    }
}

struct VoiceDebugSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VoiceInputCard()
                .environmentObject(model)
                .padding()
        }
        .background(OracleTheme.bgTop)
        .navigationTitle("Voice debug")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}
