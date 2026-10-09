import SwiftUI

struct SongInputStrip: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var voice = VoiceSongSession.shared
    @ObservedObject private var api = ApiSongSession.shared
    @ObservedObject private var card = CardSongSession.shared
    @Binding var inputModeRaw: String
    @AppStorage(SpectatorSettings.Key.count) private var spectatorCount = 1

    private let inputColumns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    private var inputMode: VoiceSettings.InputMode {
        let mode = VoiceSettings.InputMode(rawValue: inputModeRaw) ?? .card
        return mode == .manual ? .card : mode
    }

    private var songInputSummary: String {
        let spectators = spectatorCount == 2 ? " · 2 spectators" : ""
        return "\(inputMode.title)\(spectators) · how the track is chosen on Perform"
    }

    var body: some View {
        CollapsibleHomeSection(
            expandedKey: HomeSectionExpandKey.songInput,
            accent: OracleTheme.indigo,
            icon: "music.note.list",
            title: "Song",
            summary: songInputSummary,
            showsRevelationStar: true
        ) {
            VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: inputColumns, spacing: 10) {
                inputChip("Camera", icon: "camera.fill", mode: .card)
                inputChip("Voice", icon: "mic.fill", mode: .aiVoice)
                inputChip("Notes", icon: "note.text", mode: .notes)
                inputChip("API", icon: "link", mode: .api)
            }

            if !model.isPerformTrickUIActive {
                SpectatorCountBlock(inputMode: inputMode)
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
        }
        .onAppear(perform: migrateLegacyManualMode)
    }

    private func migrateLegacyManualMode() {
        guard inputModeRaw == VoiceSettings.InputMode.manual.rawValue else { return }
        inputModeRaw = VoiceSettings.InputMode.card.rawValue
        dlog("Song input migrated Manual → Camera")
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

// MARK: - Spectators (experimental)

/// Song card: 1 or 2 spectators. With 2, every input finds a second song; incoming calls still play song 1
/// and the interference test plays song 2 on the second hand.
struct SpectatorCountBlock: View {
    let inputMode: VoiceSettings.InputMode
    @AppStorage(SpectatorSettings.Key.count) private var spectatorCount = 1
    @AppStorage(WordApiSettings.Key.callerLabelEnabled) private var callerLabelEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Spectators")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OracleTheme.textPrimary)
                ExperimentalBadge()
                Spacer(minLength: 8)
                Picker("Spectators", selection: $spectatorCount) {
                    Text("1").tag(1)
                    Text("2").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 112)
            }

            if spectatorCount == 2 {
                Text(Self.howItWorks(for: inputMode))
                    .font(.caption)
                    .foregroundStyle(OracleTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Label(callerNote, systemImage: callerLabelEnabled ? "exclamationmark.triangle.fill" : "info.circle")
                    .font(.caption2)
                    .foregroundStyle(callerLabelEnabled ? OracleTheme.coral : OracleTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                SecondSpectatorSongRow()
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
        }
        .animation(.easeInOut(duration: 0.2), value: spectatorCount)
        .onChange(of: spectatorCount) { _, count in
            SecondSpectatorSong.shared.reset(reason: "spectators → \(count)")
            dlog("[SPECTATORS] → \(count)\(count == 2 ? " (experimental)" : "")")
        }
    }

    private var callerNote: String {
        callerLabelEnabled
            ? "Caller name is on. It is not part of 2-spectator mode: it keeps one phone and one word. Best to turn it off."
            : "Not for Caller name — keep Caller name off with 2 spectators."
    }

    static func howItWorks(for mode: VoiceSettings.InputMode) -> String {
        let after = "With Interference ringtone, the 1st hand brings song 1 and the 2nd hand song 2 (Perform and test). With the normal ringtone, calls play song 1."
        switch mode {
        case .card, .manual:
            return "Camera: two song titles on the card, one per line — top = spectator 1, bottom = spectator 2. One volume-up scan reads both. \(after)"
        case .aiVoice:
            return "Voice: song 1 locks as usual, then the mic keeps listening for spectator 2 and stops after song 2 locks. \(after)"
        case .notes:
            return "Notes: line 1 = spectator 1’s song, line 2 = spectator 2’s song (one song per line). \(after)"
        case .api:
            return "API: the first new search is song 1, the next new search is song 2; polling stops after song 2. \(after)"
        }
    }
}

struct ExperimentalBadge: View {
    var body: some View {
        Text("EXPERIMENTAL")
            .font(.system(size: 9, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(OracleTheme.coral)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(OracleTheme.coral.opacity(0.14), in: Capsule())
            .overlay { Capsule().strokeBorder(OracleTheme.coral.opacity(0.5), lineWidth: 0.5) }
            .accessibilityLabel("Experimental")
    }
}

/// Song 2 status (Spectators = 2): what the second spectator's input found so far.
struct SecondSpectatorSongRow: View {
    @ObservedObject private var second = SecondSpectatorSong.shared

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(second.isLocked ? OracleTheme.gold : OracleTheme.textSecondary)
            Text("Song 2")
                .font(.caption.weight(.semibold))
                .foregroundStyle(OracleTheme.textSecondary)
            Text(detail)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(second.track == nil ? OracleTheme.textSecondary : OracleTheme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        switch second.state {
        case .idle: return second.label ?? "Found on Perform or in a test"
        case .waiting: return "Waiting for spectator 2…"
        case .searching(let query): return "Searching “\(query)”…"
        case .ready: return second.label ?? "Ready"
        case .locked: return second.label ?? "Locked"
        case .notFound(let query): return "No preview for “\(query)”"
        }
    }

    private var icon: String {
        switch second.state {
        case .locked: return "lock.fill"
        case .ready: return "checkmark.circle"
        case .searching: return "magnifyingglass"
        case .notFound: return "exclamationmark.circle"
        case .idle, .waiting: return "person.2"
        }
    }
}
