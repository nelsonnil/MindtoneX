import Foundation
import QuartzCore
import UIKit

/// Notes input: the spectator writes on a white Notes-style screen. After `NotesSettings.idleDelay`
/// seconds without typing (or on Return), the note is turned into a search query and the song is
/// looked up and prefetched in the background with the normal preview lookup. A call (or a
/// manual trigger) locks whatever is ready, exactly like AI Voice.
@MainActor
final class NotesSongSession: ObservableObject {
    static let shared = NotesSongSession()

    enum Context { case perform, test }

    enum State: Equatable {
        case idle
        case writing
        case searching
        case ready
        case notFound
        case locked
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var context: Context = .test
    @Published var text = ""
    @Published private(set) var lastQuery = ""
    @Published private(set) var lastSubmitReason = ""
    @Published private(set) var readyLabel: String?

    /// True while the Notes Perform screen is up.
    var isActive: Bool { state != .idle }
    var isLocked: Bool { state == .locked }

    private var generation = 0
    private var idleTimer: Timer?
    private var searchTask: Task<Void, Never>?
    private var pendingText: String?
    private var lastSubmittedText = ""

    private init() {}

    // MARK: Lifecycle

    func start(context: Context) {
        reset(reason: "start")
        self.context = context
        state = .writing
        dlog("[NOTES] ▶︎ start (\(context == .perform ? "perform" : "test")) · \(NotesSettings.summary())")
    }

    func reset(reason: String) {
        let had = isActive || !text.isEmpty
        generation += 1
        idleTimer?.invalidate()
        idleTimer = nil
        searchTask?.cancel()
        searchTask = nil
        pendingText = nil
        lastSubmittedText = ""
        lastQuery = ""
        lastSubmitReason = ""
        readyLabel = nil
        text = ""
        state = .idle
        if had { dlog("[NOTES] ↺ reset (\(reason))") }
    }

    // MARK: Writing

    func textChanged(_ newText: String) {
        guard isActive else { return }
        text = newText
        idleTimer?.invalidate()
        idleTimer = nil
        guard !isLocked, NotesSettings.idleSearchEnabled else { return }
        let delay = NotesSettings.idleDelay
        idleTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.submit(reason: "idle \(Self.seconds(delay))") }
        }
    }

    func returnPressed() {
        guard NotesSettings.searchOnReturn else { return }
        submit(reason: "Return")
    }

    /// Checkmark on the Notes top bar: always commits what is written.
    func donePressed() {
        submit(reason: "Done")
    }

    /// Turns the note into a song lookup. Repeated calls with the same text are ignored.
    func submit(reason: String) {
        guard isActive, !isLocked else { return }
        idleTimer?.invalidate()
        idleTimer = nil
        let note = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard note.count >= 2 else { return }
        guard note != lastSubmittedText else {
            dlog("[NOTES] \(reason): text unchanged — no new search")
            return
        }
        lastSubmittedText = note
        lastSubmitReason = reason
        dlog("[NOTES] ✎ submit (\(reason)): “\(Self.oneLine(note, max: 120))”")
        pendingText = note
        runSearchLoop()
    }

    // MARK: Call

    /// A call (or a manual trigger) arrived: stop accepting new text and use what is ready.
    /// If nothing was searched yet, the current note is looked up right away.
    func callArrived(source: String) {
        guard isActive, !isLocked else { return }
        idleTimer?.invalidate()
        idleTimer = nil
        let note = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if AppModel.shared.loadState != .ready, note.count >= 2, note != lastSubmittedText {
            lastSubmittedText = note
            lastSubmitReason = "call"
            pendingText = note
            dlog("[NOTES] call/trigger (\(source)) before any search → searching “\(Self.oneLine(note, max: 80))” now")
            runSearchLoop()
        }
        lock(reason: "call/trigger (\(source))")
    }

    // MARK: Search

    private func runSearchLoop() {
        guard searchTask == nil else { return }
        let gen = generation
        state = isLocked ? .locked : .searching
        searchTask = Task { [weak self] in
            while true {
                guard let self, gen == self.generation, let note = self.pendingText else { break }
                self.pendingText = nil
                let t0 = CACurrentMediaTime()
                let query = await Self.resolveQuery(from: note)
                guard gen == self.generation else { break }
                guard let query, !query.isEmpty else {
                    dlog("[NOTES] no song in note (\(PreviewService.ms(since: t0)) ms)")
                    if !self.isLocked {
                        self.state = .notFound
                        if self.context == .perform {
                            PerformUserLog.shared.log("Notes · no song found in note")
                        }
                    }
                    continue
                }
                self.lastQuery = query
                let ok = await AppModel.shared.prepareNotesQuery(query)
                guard gen == self.generation else { break }
                let track = AppModel.shared.selected.map { "\($0.title) — \($0.artist)" }
                dlog("[NOTES] search “\(query)” → \(ok ? "ready: \(track ?? "?")" : "not found") (\(PreviewService.ms(since: t0)) ms)")
                if ok {
                    self.readyLabel = track
                    if !self.isLocked { self.state = .ready }
                    self.songReady()
                } else if !self.isLocked {
                    self.state = .notFound
                    if self.context == .perform {
                        PerformUserLog.shared.log("Notes · no match for “\(query)”")
                    }
                }
            }
            if let self, gen == self.generation { self.searchTask = nil }
        }
    }

    private func songReady() {
        if context == .perform { PerformanceCues.songLocked(source: "Notes") }
        AppModel.shared.notesSongReady(context: context)
    }

    private func lock(reason: String) {
        idleTimer?.invalidate()
        idleTimer = nil
        state = .locked
        dlog("[NOTES] 🔒 locked · \(readyLabel ?? "no song ready yet") · \(reason)")
    }

    /// Share Ringtone opens the Share sheet once a song is ready; no more searches after that.
    func lockForShare() {
        guard isActive, !isLocked else { return }
        lock(reason: "Share sheet")
    }

    /// AI (when a key is set and allowed) cleans up the note into “title artist”; otherwise the
    /// note itself is the store query.
    private static func resolveQuery(from note: String) async -> String? {
        if NotesSettings.aiAvailable, let key = VoiceSettings.apiKey {
            let transcript = "The spectator wrote this in a notes app (typed, not spoken):\n\(note)"
            do {
                let pick = try await SongPicker.openAI(transcript: transcript, previous: nil,
                                                       apiKey: key, model: VoiceSettings.pickerModel)
                if pick.hasSong, !pick.searchQuery.isEmpty {
                    dlog("[NOTES] AI → \(pick.label) · \(VoiceSongSession.percent(pick.confidence)) · \(pick.reasoning)")
                    return pick.searchQuery
                }
                dlog("[NOTES] AI found no song · \(pick.reasoning) — using the note as typed")
            } catch {
                dlog("✗ [NOTES] AI failed: \(error.localizedDescription) — using the note as typed")
            }
        }
        return oneLine(note, max: 100)
    }

    static func oneLine(_ s: String, max: Int) -> String {
        let flat = s.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        return String(flat.prefix(max))
    }

    private static func seconds(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value)) s" : String(format: "%.1f s", value)
    }
}
