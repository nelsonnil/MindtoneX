import SwiftUI

struct SongInputStrip: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var voice = VoiceSongSession.shared
    @ObservedObject private var api = ApiSongSession.shared
    @Binding var inputModeRaw: String
    @FocusState.Binding var queryFocused: Bool

    private var inputMode: VoiceSettings.InputMode {
        VoiceSettings.InputMode(rawValue: inputModeRaw) ?? .manual
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OracleEyebrow(text: "Song input")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    inputChip("Manual", icon: "keyboard", mode: .manual)
                    inputChip("AI Voice", icon: "mic.fill", mode: .aiVoice)
                    inputChip("Notes", icon: "note.text", mode: .notes)
                    inputChip("API", icon: "link", mode: .api)
                }
            }

            Group {
                switch inputMode {
                case .manual:
                    manualField
                case .aiVoice:
                    AiVoiceInputPanel()
                case .notes:
                    NotesInputControls()
                case .api:
                    ApiInputPanel()
                }
            }
        }
    }

    private func inputChip(_ title: String, icon: String, mode: VoiceSettings.InputMode) -> some View {
        let selected = inputMode == mode
        return Button {
            VoiceSongSession.shared.stopTest()
            ApiSongSession.shared.stopTest()
            let previous = inputMode
            withAnimation(.easeInOut(duration: 0.2)) { inputModeRaw = mode.rawValue }
            model.resetAfterSongInputModeChange(from: previous, to: mode)
            dlog("Song input → \(mode.title)")
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if (mode == .aiVoice && voice.isActive) || (mode == .api && api.isActive) {
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
}
