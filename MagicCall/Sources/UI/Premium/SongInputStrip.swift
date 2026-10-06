import SwiftUI

struct SongInputStrip: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var voice = VoiceSongSession.shared
    @ObservedObject private var api = ApiSongSession.shared
    @ObservedObject private var card = CardSongSession.shared
    @Binding var inputModeRaw: String

    private let inputColumns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    private var inputMode: VoiceSettings.InputMode {
        let mode = VoiceSettings.InputMode(rawValue: inputModeRaw) ?? .card
        return mode == .manual ? .card : mode
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HomeSectionTitle(
                title: "Song input",
                subtitle: "How the track is chosen before Perform",
                eyebrow: "Step 2"
            )

            LazyVGrid(columns: inputColumns, spacing: 10) {
                inputChip("Card", icon: "doc.viewfinder", mode: .card)
                inputChip("Voice", icon: "mic.fill", mode: .aiVoice)
                inputChip("Notes", icon: "note.text", mode: .notes)
                inputChip("API", icon: "link", mode: .api)
            }

            Group {
                switch inputMode {
                case .aiVoice:
                    AiVoiceInputPanel()
                case .notes:
                    NotesInputControls()
                case .api:
                    ApiInputPanel()
                case .card, .manual:
                    CardInputPanel()
                }
            }
            .animation(.easeInOut(duration: 0.2), value: inputModeRaw)
        }
        .onAppear(perform: migrateLegacyManualMode)
    }

    private func migrateLegacyManualMode() {
        guard inputModeRaw == VoiceSettings.InputMode.manual.rawValue else { return }
        inputModeRaw = VoiceSettings.InputMode.card.rawValue
        dlog("Song input migrated Manual → Card")
    }

    private func inputChip(_ title: String, icon: String, mode: VoiceSettings.InputMode) -> some View {
        let selected = inputMode == mode
        return Button {
            VoiceSongSession.shared.stopTest()
            ApiSongSession.shared.stopTest()
            CardSongSession.shared.stopTest()
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
}
