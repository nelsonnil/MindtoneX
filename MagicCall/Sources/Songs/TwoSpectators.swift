import Foundation
import QuartzCore
import SwiftUI

/// Experimental two-spectator mode: each spectator names a song. Song 1 keeps the normal slot
/// (`AppModel.selected`, played by incoming calls exactly as with one spectator); song 2 is looked up
/// and preloaded by `SecondSpectatorSong` without touching that slot. Today only the interference
/// test lab plays song 2 (second open hand).
enum SpectatorSettings {
    enum Key {
        static let count = "spectators.count"
    }

    private static var d: UserDefaults { .standard }

    static var count: Int { d.integer(forKey: Key.count) == 2 ? 2 : 1 }
    static var isTwo: Bool { count == 2 }

    static func summary() -> String { isTwo ? "2 spectators (experimental)" : "1 spectator" }
}

/// Song chosen by the second spectator (Camera, Voice, Notes or API with Spectators = 2).
@MainActor
final class SecondSpectatorSong: ObservableObject {
    static let shared = SecondSpectatorSong()

    enum Context { case perform, test }

    enum State: Equatable {
        case idle
        case waiting
        case searching(String)
        /// Preview downloaded, but the input has not settled on it yet (Voice keeps listening).
        case ready
        case locked
        case notFound(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var track: PreviewTrack?
    @Published private(set) var source: String?
    /// Preview bytes of `track` (Perform's interference ringtone needs them when the call rings).
    private(set) var trackData: Data?

    private var context: Context = .test
    private var generation = 0

    private init() {}

    var label: String? { track.map { "\($0.title) — \($0.artist)" } }
    var isLocked: Bool { state == .locked && track != nil }

    /// During Perform, song 2 has not settled yet — Auto-open Share waits for it.
    var isPendingInPerform: Bool {
        guard SpectatorSettings.isTwo, context == .perform else { return false }
        switch state {
        case .waiting, .searching, .ready, .notFound: return true
        case .idle, .locked: return false
        }
    }

    func reset(reason: String) {
        let had = state != .idle || track != nil
        generation += 1
        state = .idle
        track = nil
        trackData = nil
        source = nil
        if had { dlog("[SPECTATOR 2] ↺ reset (\(reason))") }
    }

    /// The input is now listening / watching / reading for the second spectator.
    func beginWaiting(source: String, context: Context) {
        guard SpectatorSettings.isTwo else { return }
        self.context = context
        self.source = source
        guard state == .idle else { return }
        state = .waiting
        dlog("[SPECTATOR 2] waiting for song 2 · \(source)")
    }

    /// Store search + preview download for song 2. Never touches `AppModel.selected` (song 1).
    /// A newer lookup or a reset makes an older one return nil.
    @discardableResult
    func lookup(
        queries rawQueries: [String],
        source: String,
        context: Context,
        accept: ((PreviewTrack) -> Bool)? = nil
    ) async -> PreviewTrack? {
        var queries: [String] = []
        for raw in rawQueries {
            let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard query.count >= 2, !queries.contains(where: { ApiJSON.sameText($0, query) }) else { continue }
            queries.append(query)
        }
        guard let firstQuery = queries.first else { return nil }
        generation += 1
        let gen = generation
        self.context = context
        self.source = source
        state = .searching(firstQuery)
        let previews = AppModel.shared.previews
        let t0 = CACurrentMediaTime()

        for query in queries {
            let found: [PreviewTrack]
            do {
                found = try await previews.search(query)
            } catch {
                guard gen == generation else { return nil }
                dlog("[SPECTATOR 2] search “\(query)” → \(error.localizedDescription)")
                continue
            }
            guard gen == generation else { return nil }
            guard let match = found.first(where: { accept?($0) ?? true }) else {
                dlog("[SPECTATOR 2] search “\(query)” → no acceptable match")
                continue
            }
            let data: Data
            do {
                data = try await previews.audioData(for: match)
            } catch {
                guard gen == generation else { return nil }
                dlog("[SPECTATOR 2] ✗ preview “\(match.title)”: \(error.localizedDescription)")
                continue
            }
            guard gen == generation else { return nil }
            track = match
            trackData = data
            state = .ready
            dlog("[SPECTATOR 2] ready · \(match.title) — \(match.artist) · “\(query)” · \(source) (\(PreviewService.ms(since: t0)) ms)")
            return match
        }

        guard gen == generation else { return nil }
        track = nil
        trackData = nil
        state = .notFound(firstQuery)
        dlog("[SPECTATOR 2] not found · “\(firstQuery)” · \(source)")
        if context == .perform {
            PerformUserLog.shared.log("Spectator 2 · no song found for «\(WordApiInputPanel.truncated(firstQuery, max: 40))»")
        }
        return nil
    }

    /// The input settled on song 2: Library, Perform log and the song-lock vibration.
    /// `vibrationDelay` keeps the buzz apart from song 1's when both lock in the same moment (Camera).
    func confirm(source: String, vibrationDelay: TimeInterval = 0) {
        guard let track, state != .locked else { return }
        state = .locked
        self.source = source
        let label = "\(track.title) — \(track.artist)"
        dlog("[SPECTATOR 2] 🔒 \(label) · \(source)")
        SongLibraryStore.shared.recordRecent(track, reason: "spectator2")
        guard context == .perform else { return }
        PerformLogReporter.logRecognition(.song, value: label, via: "\(source) · spectator 2")
        if PerformanceCues.vibrateOnLock {
            if vibrationDelay > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + vibrationDelay) {
                    MainActor.assumeIsolated { PerformanceCues.playSongLockVibration() }
                }
            } else {
                PerformanceCues.playSongLockVibration()
            }
        }
        AppModel.shared.autoShareOnSongLockIfEnabled(source: "\(source) · spectator 2")
    }

    /// Call, trigger, Stop or leaving Perform before song 2 settled. Song 1 is unaffected.
    func abandon(reason: String) {
        guard state != .idle, state != .locked else { return }
        generation += 1
        dlog("[SPECTATOR 2] abandoned (\(reason)) · was \(state)")
        if context == .perform {
            PerformUserLog.shared.log("Spectator 2 · no song locked (\(reason))")
        }
        state = .idle
        track = nil
        trackData = nil
    }
}

// MARK: - Song card › Spectators (experimental)

/// Song card: 1 or 2 spectators. With 2, every input finds a second song; incoming calls still play song 1
/// and the interference test plays song 2 on the second hand.
struct SpectatorCountBlock: View {
    let inputMode: VoiceSettings.InputMode
    @AppStorage(SpectatorSettings.Key.count) private var spectatorCount = 1
    @AppStorage(WordApiSettings.Key.callerLabelEnabled) private var callerLabelEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
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
