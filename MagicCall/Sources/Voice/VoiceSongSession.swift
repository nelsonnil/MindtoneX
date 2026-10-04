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

    private init() {}

    // MARK: Lifecycle

    func start(context: Context) async {
        stopListening()
        clearState()
        generation += 1
        let gen = generation
        self.context = context
        state = .starting
        dlog("[VOICE] ▶︎ start (\(context == .perform ? "perform" : "test")) · \(VoiceSettings.summary())")

        guard VoiceSettings.isConfigured else {
            fail("Add your OpenAI API key in Voice settings, or choose Apple on-device.")
            return
        }
        guard await MicCapture.requestPermission() else {
            fail("Microphone access is off. Turn it on in iPhone Settings → Privacy & Security → Microphone → \(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "RingtoneX").")
            return
        }
        let engine = VoiceSettings.engine
        if engine == .appleOnDevice {
            guard await AppleSpeechTranscriber.requestPermission() else {
                fail("Speech Recognition access is off. Turn it on in iPhone Settings → Privacy & Security → Speech Recognition.")
                return
            }
        }
        guard gen == generation else { return }

        let transcriber: LiveTranscriber
        switch engine {
        case .openAIRealtime:
            guard let key = VoiceSettings.apiKey else {
                fail("Add your OpenAI API key in Voice settings.")
                return
            }
            transcriber = OpenAIRealtimeTranscriber(apiKey: key, model: VoiceSettings.transcribeModel,
                                                    languages: VoiceSettings.language.openAICodes)
        case .appleOnDevice:
            transcriber = AppleSpeechTranscriber(locale: VoiceSettings.language.appleLocale)
        }
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
        let previous = candidate
        isThinking = true
        let t0 = CACurrentMediaTime()
        evalTask = Task { [weak self] in
            let result: Result<SongPick?, Error>
            do {
                result = .success(try await SongPicker.pick(transcript: text, previous: previous))
            } catch {
                result = .failure(error)
            }
            guard let self, gen == self.generation else { return }
            self.evalTask = nil
            self.isThinking = false
            let ms = PreviewService.ms(since: t0)
            switch result {
            case .success(let pick):
                self.lastAIError = nil
                self.handle(pick, ms: ms)
            case .failure(let error):
                self.lastAIError = error.localizedDescription
                dlog("✗ [VOICE] AI pick failed (\(ms) ms): \(error.localizedDescription)")
            }
            if self.evalPending {
                self.evalPending = false
                self.evaluate()
            }
        }
    }

    private func handle(_ pick: SongPick?, ms: Int) {
        guard state == .listening else { return }
        guard let pick, pick.hasSong, !pick.searchQuery.isEmpty else {
            dlog("[VOICE] AI (\(ms) ms): no song chosen yet\(pick.map { " · \($0.reasoning)" } ?? "")")
            return
        }
        guard pick.confidence >= VoiceSettings.minConfidence else {
            dlog("[VOICE] AI (\(ms) ms): \(pick.label) ignored, confidence \(Self.percent(pick.confidence)) < \(Self.percent(VoiceSettings.minConfidence)) · \(pick.reasoning)")
            return
        }
        if let current = candidate, current.key == pick.key {
            candidate = pick
            dlog("[VOICE] AI (\(ms) ms): same candidate \(pick.label) \(Self.percent(pick.confidence))")
            return
        }
        dlog("[VOICE] ★ candidate \(candidate?.label ?? "none") → \(pick.label) · \(Self.percent(pick.confidence)) · \(pick.reasoning) (\(ms) ms)")
        candidate = pick
        prep = .preparing
        pendingCallLock = false
        AppModel.shared.dropPreviewForNewLookup()
        restartLockTimer()
        prefetch(pick)
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
                    if !ok {
                        self.lockTimer?.invalidate()
                        self.lockDeadline = nil
                    } else if self.pendingCallLock, let c = self.candidate {
                        self.pendingCallLock = false
                        self.lock(c, reason: "call/trigger deferred until prefetch ready", duringCall: true)
                    }
                }
            }
            if let self, gen == self.generation { self.prefetchTask = nil }
        }
    }

    // MARK: Lock

    private func restartLockTimer() {
        lockTimer?.invalidate()
        let delay = VoiceSettings.lockDelay
        lockDeadline = Date().addingTimeInterval(delay)
        lockTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.lockTimerFired() }
        }
    }

    private func lockTimerFired() {
        guard state == .listening, let c = candidate else { return }
        switch prep {
        case .preparing:
            lockTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.lockTimerFired() }
            }
        case .ready:
            lock(c, reason: "\(Int(VoiceSettings.lockDelay)) s without changes", duringCall: false)
        default:
            lockDeadline = nil
        }
    }

    private func lock(_ pick: SongPick, reason: String, duringCall: Bool) {
        stopListening()
        lockedPick = pick
        lockDeadline = nil
        state = .locked
        dlog("[VOICE] 🔒 locked \(pick.label) · \(Self.percent(pick.confidence)) · \(reason) · mic running=\(mic.isRunning)")
        if context == .perform { PerformanceCues.songLocked(source: "AI Voice") }
        // During a ringing call the session category must not change (see RingtoneAudioEngine).
        if !duringCall { VoiceAudioSession.recordCategoryActive = false }
        AppModel.shared.voiceDidLock(context: context, duringCall: duringCall)
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
    }

    private func fail(_ message: String) {
        stopListening()
        state = .failed(message)
        VoiceAudioSession.recordCategoryActive = false
        VoiceAudioSession.deactivateIfIdle()
        dlog("✗ [VOICE] \(message)")
    }

    static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded())) %" }
}
