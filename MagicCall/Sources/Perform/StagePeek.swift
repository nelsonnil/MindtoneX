import SwiftUI
import UIKit

extension PerformanceCues {
    enum PeekKey {
        static let enabled = "cues.peek.enabled"
        static let fontSize = "cues.peek.fontSize"
        static let color = "cues.peek.color"
        /// 0…1 horizontal anchor in stage (leading → trailing).
        static let anchorX = "cues.peek.anchorX"
        /// 0…1 vertical anchor in stage (top → bottom).
        static let anchorY = "cues.peek.anchorY"
    }

    static let defaultPeekFontSize = 15.0
    static let peekFontSizeRange: ClosedRange<Double> = 11...28
    static let defaultPeekColor = "#FFFFFFFF"
    static let defaultPeekAnchorX = 0.5
    static let defaultPeekAnchorY = 0.72

    static func registerPeekDefaults() {
        UserDefaults.standard.register(defaults: [
            PeekKey.enabled: true,
            PeekKey.fontSize: defaultPeekFontSize,
            PeekKey.color: defaultPeekColor,
            PeekKey.anchorX: defaultPeekAnchorX,
            PeekKey.anchorY: defaultPeekAnchorY,
        ])
    }

    static var peekEnabled: Bool {
        let store = UserDefaults.standard
        return store.object(forKey: PeekKey.enabled) == nil ? true : store.bool(forKey: PeekKey.enabled)
    }
}

/// Performer-only labels while finger is held on stage.
struct StagePeekLines: Equatable {
    struct Row: Equatable, Identifiable {
        let id: String
        let title: String
        let value: String
    }

    let rows: [Row]

    static let missingValue = "— —"

    @MainActor
    static func build(model: AppModel) -> StagePeekLines {
        var rows: [Row] = []
        let twoSpectators = SpectatorSettings.isTwo
        rows.append(Row(id: "song", title: twoSpectators ? "Song 1" : "Song", value: songLine(model: model)))
        if twoSpectators {
            rows.append(Row(id: "song2", title: "Song 2", value: SecondSpectatorSong.shared.label ?? missingValue))
        }
        if InterferenceSettings.enabled {
            rows.append(Row(id: "interference", title: "Ringtone", value: model.interferenceShow.peekStatus))
        }

        if WordApiSettings.callerLabelEnabled {
            rows.append(Row(id: "caller", title: "Caller name", value: callerLine()))
        }

        if notesContactLineActive {
            rows.append(Row(id: "notes", title: "Notes", value: notesLine()))
        }

        return StagePeekLines(rows: rows)
    }

    private static var notesContactLineActive: Bool {
        NotesContactWordSettings.wordInputEnabled
            || !NotesContactSettings.storedNoteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @MainActor
    private static func songLine(model: AppModel) -> String {
        if let track = model.selected ?? model.performSessionDisplayTrack ?? model.lastReadyTrack {
            return "\(track.title) — \(track.artist)"
        }
        switch VoiceSettings.inputMode {
        case .aiVoice:
            if VoiceSongSession.shared.state == .locked,
               let pick = VoiceSongSession.shared.lockedPick?.label, !pick.isEmpty {
                return pick
            }
        case .api:
            if ApiSongSession.shared.state == .locked,
               let label = ApiSongSession.shared.lockedReading?.label, !label.isEmpty {
                return label
            }
        case .card:
            if CardSongSession.shared.isLocked,
               let label = CardSongSession.shared.candidateLabel, !label.isEmpty {
                return label
            }
        case .notes:
            if NotesSongSession.shared.isLocked, let track = model.selected {
                return "\(track.title) — \(track.artist)"
            }
        case .manual:
            break
        }
        return missingValue
    }

    @MainActor
    private static func callerLine() -> String {
        let session = WordApiSession.shared
        if let locked = session.lockedReading?.label.trimmingCharacters(in: .whitespacesAndNewlines), !locked.isEmpty {
            return locked
        }
        if let last = session.lastReading?.label.trimmingCharacters(in: .whitespacesAndNewlines), !last.isEmpty {
            return last
        }
        return missingValue
    }

    @MainActor
    private static func notesLine() -> String {
        let wordSession = NotesContactWordSession.shared
        let word = wordSession.lockedReading?.label
            ?? wordSession.lastReading?.label
        let resolved = NotesContactSettings.resolvedContactNote(lockedWord: word)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if resolved.isEmpty { return missingValue }
        return resolved
    }
}

struct StagePeekOverlay: View {
    let lines: StagePeekLines
    let fontSize: Double
    let colorHex: String
    let anchorX: Double
    let anchorY: Double

    var body: some View {
        GeometryReader { geo in
            let textColor = Color(hex: colorHex) ?? .white
            VStack(alignment: .leading, spacing: 6) {
                ForEach(lines.rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(row.title)
                            .font(.system(size: fontSize * 0.78, weight: .semibold))
                            .foregroundStyle(textColor.opacity(0.72))
                        Text(row.value)
                            .font(.system(size: fontSize, weight: .medium))
                            .foregroundStyle(textColor)
                            .lineLimit(2)
                            .minimumScaleFactor(0.65)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.black.opacity(0.42))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .position(
                x: geo.size.width * anchorX,
                y: geo.size.height * anchorY
            )
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
        .transition(.opacity)
    }
}

/// Feedback card mini-preview — drag to set peek position on stage.
struct StagePeekLayoutPreview: View {
    @Binding var anchorX: Double
    @Binding var anchorY: Double
    @Binding var fontSize: Double
    @Binding var colorHex: String

    private let sample = StagePeekLines(rows: [
        .init(id: "song", title: "Song", value: "Lose Yourself — Eminem"),
        .init(id: "caller", title: "Caller name", value: "NERVOUS"),
        .init(id: "notes", title: "Notes", value: "Remember {word}"),
    ])

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview · drag the block")
                .font(.caption2)
                .foregroundStyle(OracleTheme.textSecondary)

            GeometryReader { geo in
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                    if StageImageStore.hasScreenshot, let ui = StageImageStore.loadUIImage() {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .opacity(0.85)
                            // scaledToFill overflows the 168 pt box; clipping is visual only, so the
                            // overflow would swallow taps on the Feedback switches above.
                            .allowsHitTesting(false)
                    }

                    peekPreviewBlock
                        .position(x: geo.size.width * anchorX, y: geo.size.height * anchorY)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let x = min(max(value.location.x / geo.size.width, 0.08), 0.92)
                                    let y = min(max(value.location.y / geo.size.height, 0.12), 0.92)
                                    anchorX = x
                                    anchorY = y
                                }
                        )
                }
            }
            .frame(height: 168)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
            }
        }
    }

    private var peekPreviewBlock: some View {
        let textColor = Color(hex: colorHex) ?? .white
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(sample.rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(row.title)
                        .font(.system(size: fontSize * 0.78, weight: .semibold))
                        .foregroundStyle(textColor.opacity(0.72))
                    Text(row.value)
                        .font(.system(size: fontSize * 0.9, weight: .medium))
                        .foregroundStyle(textColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.black.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

extension StageImageStore {
    static func loadUIImage() -> UIImage? {
        guard hasScreenshot else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}
