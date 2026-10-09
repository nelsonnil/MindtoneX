import Foundation
import QuartzCore

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
