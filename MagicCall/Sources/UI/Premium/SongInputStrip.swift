import SwiftUI

struct SongInputStrip: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var voice = VoiceSongSession.shared
    @ObservedObject private var api = ApiSongSession.shared
    @Binding var inputModeRaw: String
    @FocusState.Binding var queryFocused: Bool

    private let inputColumns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    private var inputMode: VoiceSettings.InputMode {
        VoiceSettings.InputMode(rawValue: inputModeRaw) ?? .manual
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HomeSectionTitle(
                eyebrow: "Step 2",
                title: "Song input",
                subtitle: "How the track is chosen before Perform"
            )

            LazyVGrid(columns: inputColumns, spacing: 10) {
                inputChip("Manual", icon: "keyboard", mode: .manual)
                inputChip("AI Voice", icon: "mic.fill", mode: .aiVoice)
                inputChip("Notes", icon: "note.text", mode: .notes)
                inputChip("API", icon: "link", mode: .api)
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
            .animation(.easeInOut(duration: 0.2), value: inputModeRaw)
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
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.title2.weight(.semibold))
                    if (mode == .aiVoice && voice.isActive) || (mode == .api && api.isActive) {
                        Circle().fill(Color.red).frame(width: 7, height: 7)
                            .offset(x: 4, y: -4)
                    }
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 72)
            .foregroundStyle(selected ? OracleTheme.textPrimary : OracleTheme.textSecondary)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [OracleTheme.indigo.opacity(0.38), OracleTheme.deepIndigo.opacity(0.22)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        selected
                            ? LinearGradient(
                                colors: [OracleTheme.gold.opacity(0.85), OracleTheme.indigo.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(colors: [OracleTheme.cardBorder], startPoint: .top, endPoint: .bottom),
                        lineWidth: selected ? 1.5 : 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
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
                    .padding(14)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button {
                    queryFocused = false
                    Task { await model.search() }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.body.weight(.semibold))
                        .frame(width: 48, height: 48)
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
                .padding(12)
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
