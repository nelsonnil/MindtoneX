import AVFoundation
import Foundation
import QuartzCore
import UIKit

/// Listens to the conversation, asks the AI which song the spectator finally chose, prefetches
/// every new candidate and locks the song after `VoiceSettings.lockDelay` seconds without changes.
@MainActor
final class VoiceSongSession: ObservableObject {
    static let shared = VoiceSongSession()

    enum Context { case perform, test }

    enum State: Equatable {
        case idle
        case starting
        case listening
        case locked
        case failed(String)
    }

    enum Prep: Equatable { case preparing, ready, notFound }

    struct Line: Identifiable, Equatable {
        let id: String
        var text: String
        var isFinal: Bool
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var context: Context = .test
    @Published private(set) var lines: [Line] = []
    @Published private(set) var candidate: SongPick?
    @Published private(set) var prep: Prep?
    @Published private(set) var lockedPick: SongPick?
    @Published private(set) var lockDeadline: Date?
    @Published private(set) var isThinking = false
    @Published private(set) var lastAIError: String?
    @Published private(set) var level: Float = 0
    @Published private(set) var callerWordCandidate: WordPick?
    @Published private(set) var notesWordCandidate: WordPick?
    /// Spectators = 2: song 1 is in `lockedPick` and the mic keeps listening for the second spectator.
    @Published private(set) var listeningForSecondSong = false
    @Published private(set) var secondCandidate: SongPick?
    @Published private(set) var secondPrep: Prep?
    @Published private(set) var secondLockedPick: SongPick?

    var isActive: Bool { state == .starting || state == .listening }
    var hasContent: Bool { !lines.isEmpty || candidate != nil || lockedPick != nil || state != .idle }

    var transcriptText: String {
        lines.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private let mic = MicCapture()
    private var transcriber: LiveTranscriber?
    private var generation = 0
    private var debounce: Timer?
    private var lockTimer: Timer?
    private var evalTask: Task<Void, Never>?
    private var evalPending = false
    private var lastEvaluatedText = ""
    private var prefetchTask: Task<Void, Never>?
    private var pendingPrefetch: SongPick?
    private var pendingCallLock = false
    /// First transcript line that belongs to the second spectator's turn.
    private var secondTranscriptStart = 0
    private var secondPrefetchTask: Task<Void, Never>?
    private var pendingSecondPrefetch: SongPick?
    /// Two-song: a later distinct title arrived while song 1 is still prefetching.
    private var pendingSecondPick: SongPick?

    private init() {}

    // MARK: Lifecycle

    func start(context: Context) async {
        stopListening()
        clearState()
        generation += 1
        let gen = generation
        self.context = context
        state = .starting
        if context == .test, SpectatorSettings.isTwo {
            SecondSpectatorSong.shared.reset(reason: "voice test")
        }
        dlog("[VOICE] ▶︎ start (\(context == .perform ? "perform" : "test")) · \(VoiceSettings.summary()) · \(SpectatorSettings.summary())")

        guard VoiceSettings.isConfigured else {
            fail("Add your OpenAI API key under Performance settings.")
            return
        }
        guard await MicCapture.requestPermission() else {
            fail("Microphone access is off. Turn it on in iPhone Settings → Privacy & Security → Microphone → \(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "MindtoneX").")
            return
        }
        guard gen == generation else { return }

        guard let key = VoiceSettings.apiKey else {
            fail("Add your OpenAI API key under Performance settings.")
            return
        }
        let transcriber: LiveTranscriber = OpenAIRealtimeTranscriber(
            apiKey: key,
            model: VoiceSettings.transcribeModel,
            languages: VoiceSettings.openAILanguageCodes
        )
        transcriber.onUpdate = { [weak self] id, text, isFinal in
            MainActor.assumeIsolated { self?.ingest(id: id, text: text, isFinal: isFinal, gen: gen) }
        }
        transcriber.onError = { [weak self] message in
            MainActor.assumeIsolated {
                guard let self, gen == self.generation, self.isActive else { return }
                self.fail(message)
            }
        }

        do {
            try VoiceAudioSession.activateForListening()
            mic.producePCM16 = transcriber.wantsPCM16
            let meter = LevelThrottle()
            meter.onLevel = { [weak self] level, _ in
                MainActor.assumeIsolated { self?.level = level }
            }
            mic.onAudio = MicCapture.makeHandler(transcriber: transcriber, meter: meter)
            try transcriber.start()
            try mic.start()
            self.transcriber = transcriber
            state = .listening
            dlog("[VOICE] listening · audio=\(AVAudioSession.sharedInstance().category.rawValue) in=\(MicCapture.inputDescription()) out=\(RingtoneAudioEngine.routeDescription())")
        } catch {
            transcriber.stop()
            fail("Could not start listening: \(RingtoneAudioEngine.describe(error))")
        }
    }

    /// Test screen "Stop": stops the mic but keeps what was heard on screen.
    func stopTest() {
        guard isActive else { return }
        stopListening()
        if listeningForSecondSong {
            listeningForSecondSong = false
            SecondSpectatorSong.shared.abandon(reason: "voice test stopped")
        }
        state = .idle
        lockDeadline = nil
        VoiceAudioSession.recordCategoryActive = false
        VoiceAudioSession.deactivateIfIdle()
        dlog("[VOICE] ■ test stopped")
    }

    /// Clears transcript, candidate and locked song (called when leaving Perform).
    func reset(reason: String) {
        let had = hasContent
        generation += 1
        stopListening()
        clearState()
        VoiceAudioSession.recordCategoryActive = false
        if had { dlog("[VOICE] ↺ reset (\(reason))") }
    }

    /// A call (or a manual trigger) arrived: use the best candidate right away.
    func callArrived(source: String) {
        guard isActive else { return }
        if listeningForSecondSong {
            finishSecondSpectator(reason: "call/trigger (\(source))", duringCall: true)
            return
        }
        if let c = candidate, prep == .ready {
            pendingCallLock = false
            lock(c, reason: "call/trigger before lock (\(source))", duringCall: true)
        } else if candidate != nil, prep == .preparing {
            pendingCallLock = true
            dlog("[VOICE] call/trigger (\(source)) while prefetch in progress — lock when audio ready")
        } else {
            pendingCallLock = false
            dlog("[VOICE] call/trigger (\(source)) with no usable candidate — stopping mic")
            stopListening()
            state = .idle
        }
    }

    // MARK: Transcript

    private func ingest(id: String, text: String, isFinal: Bool, gen: Int) {
        guard gen == generation, state == .listening else { return }
        if let i = lines.firstIndex(where: { $0.id == id }) {
            lines[i].text = text
            lines[i].isFinal = isFinal
        } else {
            lines.append(Line(id: id, text: text, isFinal: isFinal))
        }
        if isFinal {
            dlog("[VOICE] heard: “\(text)”")
            if context == .perform {
                PerformLogReporter.logVoiceHeard(text)
            }
            scheduleEvaluation(after: 0.05)
        } else {
            scheduleEvaluation(after: 0.9)
        }
    }

    // MARK: AI evaluation

    private func scheduleEvaluation(after delay: TimeInterval) {
        debounce?.invalidate()
        debounce = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
    }

    private func evaluate() {
        guard state == .listening else { return }
        guard evalTask == nil else {
            evalPending = true
            return
        }
        let text = transcriptText
        guard text.count >= 3, text != lastEvaluatedText else { return }
        lastEvaluatedText = text
        let gen = generation
        let secondSong = listeningForSecondSong
        let previous = secondSong ? secondCandidate : candidate
        let songTranscript = secondSong ? secondSpectatorTranscript : text
        let songContext: String?
        if secondSong {
            songContext = secondSpectatorPromptContext
        } else if SpectatorSettings.isTwo {
            songContext = Self.firstOfTwoPromptContext
        } else {
            songContext = nil
        }
        isThinking = true
        let t0 = CACurrentMediaTime()
        let plan = VoiceListenPlan.current
        evalTask = Task { [weak self] in
            guard let self, gen == self.generation else { return }
            defer {
                if gen == self.generation {
                    self.evalTask = nil
                    self.isThinking = false
                    if self.evalPending {
                        self.evalPending = false
                        self.evaluate()
                    }
                }
            }
            do {
                if plan.song, songTranscript.count >= 3 {
                    let pick = try await SongPicker.pick(transcript: songTranscript, previous: previous, context: songContext)
                    guard gen == self.generation else { return }
                    self.lastAIError = nil
                    let ms = PreviewService.ms(since: t0)
                    if self.context == .perform {
                        PerformLogReporter.logOpenAISongAnswer(pick, ms: ms)
                    }
                    if secondSong {
                        self.handleSecond(pick, ms: ms)
                    } else {
                        self.handle(pick, ms: ms)
                        await self.pickSecondSongIfNamedInSameTranscript(
                            fullText: text,
                            gen: gen,
                            lastIsFinal: self.lines.last?.isFinal == true
                        )
                    }
                }
                if plan.callerName {
                    let tWord = CACurrentMediaTime()
                    let pick = try await SpectatorWordPicker.pick(
                        channel: .callerName,
                        transcript: text,
                        previous: self.callerWordCandidate
                    )
                    guard gen == self.generation else { return }
                    if self.context == .perform {
                        PerformLogReporter.logOpenAIWordAnswer(
                            channel: .callerName,
                            pick: pick,
                            ms: PreviewService.ms(since: tWord)
                        )
                    }
                    self.handleWordPick(pick, channel: .callerName)
                }
                if plan.notesContact {
                    let tWord = CACurrentMediaTime()
                    let pick = try await SpectatorWordPicker.pick(
                        channel: .notesContact,
                        transcript: text,
                        previous: self.notesWordCandidate
                    )
                    guard gen == self.generation else { return }
                    if self.context == .perform {
                        PerformLogReporter.logOpenAIWordAnswer(
                            channel: .notesContact,
                            pick: pick,
                            ms: PreviewService.ms(since: tWord)
                        )
                    }
                    self.handleWordPick(pick, channel: .notesContact)
                }
            } catch {
                guard gen == self.generation else { return }
                self.lastAIError = error.localizedDescription
                if self.context == .perform {
                    PerformUserLog.shared.log("OpenAI · error · \(error.localizedDescription)")
                }
                dlog("✗ [VOICE] AI evaluate failed: \(error.localizedDescription)")
            }
        }
    }

    private func handleWordPick(_ pick: WordPick?, channel: SpectatorListenChannel) {
        guard state == .listening || state == .locked else { return }
        guard let pick, pick.hasWord else { return }
        let word = pick.normalizedWord
        guard word.count >= 2 else { return }
        guard pick.confidence >= VoiceSettings.minConfidence else {
            dlog("[VOICE] \(channel.title) word ignored · confidence \(Self.percent(pick.confidence))")
            if context == .perform {
                PerformUserLog.shared.log(
                    "Voice · \(channel.title) ignored · confidence \(Self.percent(pick.confidence)) below minimum"
                )
            }
            return
        }
        switch channel {
        case .callerName:
            if callerWordCandidate?.word == word { return }
            callerWordCandidate = pick
            dlog("[VOICE] ★ caller name word → «\(word)» · \(pick.reasoning)")
            if WordApiSession.shared.state != .locked {
                WordApiSession.shared.ingestVoiceWord(word)
            }
        case .notesContact:
            if notesWordCandidate?.word == word { return }
            notesWordCandidate = pick
            dlog("[VOICE] ★ notes contact word → «\(word)» · \(pick.reasoning)")
            if NotesContactWordSession.shared.state != .locked {
                NotesContactWordSession.shared.ingestVoiceWord(word)
            }
        case .song:
            break
        }
    }

    private func handle(_ pick: SongPick?, ms: Int) {
        guard state == .listening, !listeningForSecondSong else { return }
        let resolved = resolvedSongPick(pick, transcript: transcriptText)
        guard let resolved, resolved.hasSong, resolved.hasUsableTitle else {
            dlog("[VOICE] AI (\(ms) ms): no song chosen yet\(pick.map { " · \($0.reasoning)" } ?? "")")
            return
        }
        let floor = Self.confidenceFloor(for: resolved)
        guard resolved.confidence >= floor else {
            dlog("[VOICE] AI (\(ms) ms): \(resolved.label) ignored, confidence \(Self.percent(resolved.confidence)) < \(Self.percent(floor)) · \(resolved.reasoning)")
            if context == .perform {
                PerformUserLog.shared.log(
                    "Voice · song ignored · «\(WordApiInputPanel.truncated(resolved.label, max: 40))» · confidence \(Self.percent(resolved.confidence)) below minimum"
                )
            }
            return
        }
        if SpectatorSettings.isTwo, let current = candidate, current.key != resolved.key,
           !resolved.refines(current),
           !Self.transcriptRetractsPreviousChoice(transcriptText) {
            promoteFirstSongAndTakeSecond(first: current, second: resolved, ms: ms)
            return
        }
        if let current = candidate, current.key == resolved.key {
            candidate = resolved
            dlog("[VOICE] AI (\(ms) ms): same candidate \(resolved.label) \(Self.percent(resolved.confidence))")
            return
        }
        pendingSecondPick = nil
        dlog("[VOICE] ★ candidate \(candidate?.label ?? "none") → \(resolved.label) · \(Self.percent(resolved.confidence)) · \(resolved.reasoning) (\(ms) ms)")
        candidate = resolved
        prep = .preparing
        pendingCallLock = false
        AppModel.shared.dropPreviewForNewLookup()
        restartLockTimer()
        prefetch(resolved)
    }

    // MARK: Prefetch

    private func prefetch(_ pick: SongPick) {
        pendingPrefetch = pick
        guard prefetchTask == nil else { return }
        let gen = generation
        prefetchTask = Task { [weak self] in
            while true {
                guard let self, gen == self.generation, let next = self.pendingPrefetch else { break }
                self.pendingPrefetch = nil
                let t0 = CACurrentMediaTime()
                let ok = await AppModel.shared.prepareVoiceCandidate(next)
                guard gen == self.generation else { break }
                let track = AppModel.shared.selected.map { "\($0.title) — \($0.artist)" } ?? "?"
                dlog("[VOICE] prefetch “\(next.searchQuery)” → \(ok ? "ready: \(track)" : "not found") (\(PreviewService.ms(since: t0)) ms)")
                if self.candidate?.key == next.key {
                    self.prep = ok ? .ready : .notFound
                    if !ok, self.context == .perform {
                        PerformUserLog.shared.log("Voice · no match for “\(next.label)”")
                    }
                    if ok {
                        await MainActor.run {
                            AppModel.shared.recordRecentLoadedSongIfReady(reason: "voicePrefetch")
                        }
                    }
                    if !ok {
                        self.lockTimer?.invalidate()
                        self.lockDeadline = nil
                    } else if self.pendingCallLock, let c = self.candidate {
                        self.pendingCallLock = false
                        self.lock(c, reason: "call/trigger deferred until prefetch ready", duringCall: true)
                    } else if let second = self.pendingSecondPick, ok, let first = self.candidate {
                        self.pendingSecondPick = nil
                        self.promoteFirstSongAndTakeSecond(first: first, second: second, ms: 0)
                    }
                }
            }
            if let self, gen == self.generation { self.prefetchTask = nil }
        }
    }

    // MARK: Lock

    /// Artist-only candidates wait longer so the spectator can still add a title.
    private var activeLockDelay: Double {
        let pick = listeningForSecondSong ? secondCandidate : candidate
        return VoiceSettings.lockDelay + (pick?.isArtistOnly == true ? Self.artistOnlyExtraLockDelay : 0)
    }

    private func restartLockTimer() {
        lockTimer?.invalidate()
        let delay = activeLockDelay
        lockDeadline = Date().addingTimeInterval(delay)
        lockTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.lockTimerFired() }
        }
    }

    private func lockTimerFired() {
        if listeningForSecondSong {
            secondLockTimerFired()
            return
        }
        guard state == .listening, let c = candidate else { return }
        switch prep {
        case .preparing:
            lockTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.lockTimerFired() }
            }
        case .ready:
            lock(c, reason: "\(Int(activeLockDelay)) s without changes", duringCall: false)
        default:
            lockDeadline = nil
        }
    }

    private func lock(_ pick: SongPick, reason: String, duringCall: Bool) {
        if SpectatorSettings.isTwo, !duringCall, lockedPick == nil {
            lockFirstOfTwo(pick, reason: reason)
            return
        }
        stopListening()
        lockedPick = pick
        lockDeadline = nil
        state = .locked
        dlog("[VOICE] 🔒 locked \(pick.label) · \(Self.percent(pick.confidence)) · \(reason) · mic running=\(mic.isRunning)")
        if context == .perform {
            PerformanceCues.songLocked(source: "Voice")
            let loaded = AppModel.shared.selected ?? AppModel.shared.lastReadyTrack
            SongLibraryStore.shared.commitPerformSnapshot(
                RecentPerformSnapshot(pick: pick.filled(from: loaded), previewURL: loaded?.previewURL.absoluteString)
            )
            AppModel.shared.notePerformDisplayTrack()
        }
        if SpectatorSettings.isTwo {
            SecondSpectatorSong.shared.abandon(reason: "call before song 1 locked")
        }
        // During a ringing call the session category must not change (see RingtoneAudioEngine).
        if !duringCall { VoiceAudioSession.recordCategoryActive = false }
        AppModel.shared.voiceDidLock(context: context, duringCall: duringCall)
    }

    // MARK: Second spectator (Spectators = 2)

    /// Song 1 locks like with one spectator, but the mic and transcriber keep running for spectator 2.
    private func lockFirstOfTwo(_ pick: SongPick, reason: String) {
        lockTimer?.invalidate()
        lockTimer = nil
        lockDeadline = nil
        lockedPick = pick
        listeningForSecondSong = true
        secondCandidate = nil
        secondPrep = nil
        secondLockedPick = nil
        secondTranscriptStart = lines.firstIndex(where: { !$0.isFinal }) ?? lines.count
        dlog("[VOICE] 🔒 song 1 of 2 · \(pick.label) · \(Self.percent(pick.confidence)) · \(reason) · mic stays on for spectator 2 (transcript from line \(secondTranscriptStart))")
        SecondSpectatorSong.shared.beginWaiting(source: "Voice", context: context == .perform ? .perform : .test)
        if context == .perform {
            PerformanceCues.songLocked(source: "Voice · song 1")
            let loaded = AppModel.shared.selected ?? AppModel.shared.lastReadyTrack
            SongLibraryStore.shared.commitPerformSnapshot(
                RecentPerformSnapshot(pick: pick.filled(from: loaded), previewURL: loaded?.previewURL.absoluteString)
            )
            AppModel.shared.notePerformDisplayTrack()
            PerformUserLog.shared.log("Voice · song 1 locked · listening for song 2")
        }
        AppModel.shared.voiceFirstOfTwoLocked(context: context)
    }

    /// What was said after song 1 locked.
    private var secondSpectatorTranscript: String {
        lines.dropFirst(secondTranscriptStart)
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static let firstOfTwoPromptContext =
        "Two-song mode. Return ONLY song 1: the first title the spectator settles on. "
        + "If a later distinct title also appears, ignore it here (that is song 2). "
        + "Last-commitment-wins applies only to a mind-change of song 1 («no, mejor X»), not to a second song. "
        + "Title without artist is enough — infer the most popular recording. "
        + "An artist alone is enough too (title empty); a title by that same artist right after it refines song 1, it is not song 2."

    private var secondSpectatorPromptContext: String? {
        songTwoPromptContext(for: lockedPick)
    }

    private func songTwoPromptContext(for first: SongPick?) -> String? {
        guard let first else { return nil }
        let artistOnlyNote = first.isArtistOnly
            ? "Song 1 was named by artist only («\(first.artist)»): a title by \(first.artist) is still song 1, not song 2. "
            : ""
        return "Two-song mode. Song 1 «\(first.label)» is already chosen. "
            + artistOnlyNote
            + "Return song 2: the next distinct title (same person or a second person). "
            + "Title without artist is enough — infer the most popular recording. An artist alone is enough too (title empty). "
            + "Never return «\(first.label)» again: if it is the only song mentioned, return has_song=false."
    }

    private func handleSecond(_ pick: SongPick?, ms: Int) {
        guard state == .listening, listeningForSecondSong else { return }
        let resolved = resolvedSongPick(pick, transcript: secondSpectatorTranscript)
        guard let resolved, resolved.hasSong, resolved.hasUsableTitle else {
            dlog("[VOICE] AI (\(ms) ms): spectator 2 · no song yet\(pick.map { " · \($0.reasoning)" } ?? "")")
            return
        }
        let floor = Self.confidenceFloor(for: resolved)
        guard resolved.confidence >= floor else {
            dlog("[VOICE] AI (\(ms) ms): spectator 2 · \(resolved.label) ignored, confidence \(Self.percent(resolved.confidence)) < \(Self.percent(floor))")
            if context == .perform {
                PerformUserLog.shared.log(
                    "Voice · song 2 ignored · «\(WordApiInputPanel.truncated(resolved.label, max: 40))» · confidence \(Self.percent(resolved.confidence)) below minimum"
                )
            }
            return
        }
        if let first = lockedPick, first.key == resolved.key {
            dlog("[VOICE] AI (\(ms) ms): spectator 2 · same as song 1 (\(resolved.label)) — ignored")
            return
        }
        if let current = secondCandidate, current.key == resolved.key {
            secondCandidate = resolved
            return
        }
        dlog("[VOICE] ★ spectator 2 candidate \(secondCandidate?.label ?? "none") → \(resolved.label) · \(Self.percent(resolved.confidence)) · \(resolved.reasoning) (\(ms) ms)")
        secondCandidate = resolved
        secondPrep = .preparing
        restartLockTimer()
        prefetchSecond(resolved)
    }

    /// Song 2 loads next to song 1 (`SecondSpectatorSong`), never into the Home slot.
    private func prefetchSecond(_ pick: SongPick) {
        pendingSecondPrefetch = pick
        guard secondPrefetchTask == nil else { return }
        let gen = generation
        let lookupContext: SecondSpectatorSong.Context = context == .perform ? .perform : .test
        secondPrefetchTask = Task { [weak self] in
            while true {
                guard let self, gen == self.generation, let next = self.pendingSecondPrefetch else { break }
                self.pendingSecondPrefetch = nil
                let track = await SecondSpectatorSong.shared.lookup(
                    queries: next.allStoreSearchQueries,
                    source: "Voice",
                    context: lookupContext
                )
                guard gen == self.generation else { break }
                if self.secondCandidate?.key == next.key {
                    self.secondPrep = track != nil ? .ready : .notFound
                    if track == nil {
                        self.lockTimer?.invalidate()
                        self.lockDeadline = nil
                        if self.context == .perform {
                            PerformUserLog.shared.log("Voice · song 2 · no match for “\(next.label)”")
                        }
                    }
                }
            }
            if let self, gen == self.generation { self.secondPrefetchTask = nil }
        }
    }

    private func secondLockTimerFired() {
        guard state == .listening, listeningForSecondSong, let c = secondCandidate else { return }
        switch secondPrep {
        case .preparing:
            lockTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.lockTimerFired() }
            }
        case .ready:
            lockSecond(c, reason: "\(Int(activeLockDelay)) s without changes", duringCall: false)
        default:
            lockDeadline = nil
        }
    }

    /// Song 2 locked: the mic stops here (same moment as the single-spectator lock).
    private func lockSecond(_ pick: SongPick, reason: String, duringCall: Bool) {
        stopListening()
        listeningForSecondSong = false
        secondLockedPick = pick
        lockDeadline = nil
        state = .locked
        dlog("[VOICE] 🔒 song 2 of 2 · \(pick.label) · \(Self.percent(pick.confidence)) · \(reason) · mic running=\(mic.isRunning)")
        if context == .perform {
            PerformUserLog.shared.log("Voice · song 2 locked · «\(WordApiInputPanel.truncated(pick.label, max: 40))» · mic off")
        }
        SecondSpectatorSong.shared.confirm(source: "Voice")
        if !duringCall { VoiceAudioSession.recordCategoryActive = false }
        AppModel.shared.voiceDidLock(context: context, duringCall: duringCall)
    }

    /// A call or trigger arrived while listening for spectator 2: keep song 1, take song 2 only if ready.
    private func finishSecondSpectator(reason: String, duringCall: Bool) {
        if let c = secondCandidate, secondPrep == .ready {
            lockSecond(c, reason: reason, duringCall: duringCall)
            return
        }
        stopListening()
        listeningForSecondSong = false
        lockDeadline = nil
        state = .locked
        dlog("[VOICE] spectator 2 not locked (\(reason)) · song 1 stays")
        SecondSpectatorSong.shared.abandon(reason: reason)
        if !duringCall { VoiceAudioSession.recordCategoryActive = false }
        AppModel.shared.voiceDidLock(context: context, duringCall: duringCall)
    }

    // MARK: Title-only + two-song helpers

    private static let titleOnlyConfidenceFloor = 0.35
    private static let artistOnlyExtraLockDelay = 2.0

    private static func confidenceFloor(for pick: SongPick) -> Double {
        pick.isTitleOnly || pick.isArtistOnly
            ? min(VoiceSettings.minConfidence, titleOnlyConfidenceFloor)
            : VoiceSettings.minConfidence
    }
    private static let retractCues = [
        "no, mejor", "no mejor", "o no", "espera", "cambio", "la otra",
        "actually", "wait", "better", "changed my mind", "change",
    ]

    private func resolvedSongPick(_ pick: SongPick?, transcript: String) -> SongPick? {
        if let pick, pick.hasSong, pick.hasUsableTitle {
            return pick.withFilledSearchQuery()
        }
        guard let guess = SongPicker.heuristic(transcript: transcript), guess.hasUsableTitle else {
            return pick?.hasSong == true ? pick?.withFilledSearchQuery() : nil
        }
        return guess.withFilledSearchQuery()
    }

    private static func transcriptRetractsPreviousChoice(_ text: String) -> Bool {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
        return retractCues.contains(where: { folded.contains($0) })
    }

    private func promoteFirstSongAndTakeSecond(first: SongPick, second: SongPick, ms: Int) {
        switch prep {
        case .ready:
            dlog("[VOICE] two songs · second title «\(second.label)» while song 1 ready — lock song 1 now")
            lockFirstOfTwo(first, reason: "second title heard — lock song 1")
            handleSecond(second, ms: ms)
        case .preparing:
            pendingSecondPick = second
            dlog("[VOICE] two songs · second title «\(second.label)» queued until song 1 audio is ready")
        default:
            pendingSecondPick = nil
            candidate = second
            prep = .preparing
            pendingCallLock = false
            AppModel.shared.dropPreviewForNewLookup()
            restartLockTimer()
            prefetch(second)
        }
    }

    private func pickSecondSongIfNamedInSameTranscript(fullText: String, gen: Int, lastIsFinal: Bool) async {
        guard gen == generation, SpectatorSettings.isTwo, lastIsFinal else { return }
        guard state == .listening, !listeningForSecondSong, let first = candidate else { return }
        guard let context = songTwoPromptContext(for: first) else { return }
        do {
            let pick = try await SongPicker.pick(transcript: fullText, previous: nil, context: context)
            guard gen == self.generation, self.state == .listening, !self.listeningForSecondSong else { return }
            let resolved = resolvedSongPick(pick, transcript: fullText)
            guard let resolved, resolved.hasSong, resolved.hasUsableTitle, resolved.key != first.key,
                  !resolved.refines(first) else { return }
            dlog("[VOICE] two songs · same transcript also names song 2 «\(resolved.label)»")
            promoteFirstSongAndTakeSecond(first: first, second: resolved, ms: 0)
        } catch {
            dlog("[VOICE] two songs · song 2 peek failed: \(error.localizedDescription)")
        }
    }

    // MARK: Helpers

    private func stopListening() {
        debounce?.invalidate()
        debounce = nil
        lockTimer?.invalidate()
        lockTimer = nil
        mic.stop()
        mic.onAudio = nil
        transcriber?.stop()
        transcriber = nil
        evalTask?.cancel()
        evalTask = nil
        evalPending = false
        isThinking = false
        level = 0
    }

    private func clearState() {
        state = .idle
        lines = []
        candidate = nil
        prep = nil
        lockedPick = nil
        lockDeadline = nil
        lastAIError = nil
        lastEvaluatedText = ""
        pendingPrefetch = nil
        prefetchTask?.cancel()
        prefetchTask = nil
        pendingCallLock = false
        callerWordCandidate = nil
        notesWordCandidate = nil
        listeningForSecondSong = false
        secondCandidate = nil
        secondPrep = nil
        secondLockedPick = nil
        secondTranscriptStart = 0
        pendingSecondPrefetch = nil
        secondPrefetchTask?.cancel()
        secondPrefetchTask = nil
        pendingSecondPick = nil
    }

    private func fail(_ message: String) {
        stopListening()
        listeningForSecondSong = false
        state = .failed(message)
        if context == .perform {
            PerformUserLog.shared.log("Voice · \(message)")
        }
        VoiceAudioSession.recordCategoryActive = false
        VoiceAudioSession.deactivateIfIdle()
        dlog("✗ [VOICE] \(message)")
    }

    static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded())) %" }
}
