import Foundation
import QuartzCore

/// Polls / Card OCR for the **Notes contact** chip word — independent of Caller name.
@MainActor
final class NotesContactWordSession: ObservableObject {
    static let shared = NotesContactWordSession()

    enum Context { case perform, test }

    enum State: Equatable {
        case idle
        case connecting
        case watching
        case locked
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var context: Context = .test
    @Published private(set) var provider: NotesContactWordSettings.Provider = .inject
    @Published private(set) var baseline: WordReading?
    @Published private(set) var lastReading: WordReading?
    @Published private(set) var lockedReading: WordReading?
    @Published private(set) var lastError: String?
    @Published private(set) var consecutiveErrors = 0
    @Published private(set) var pollCount = 0

    var isActive: Bool {
        switch state {
        case .connecting, .watching, .locked:
            if provider == .card || provider == .voice { return true }
            return timer != nil
        default: return false
        }
    }

    private var timer: Timer?
    private var isRefreshing = false
    private var generation = 0
    private var previousPollReading: WordReading?
    private var lastAppliedLabel: String?

    private init() {}

    func start(context: Context) {
        stopPolling()
        clearState()
        generation += 1
        self.context = context
        provider = NotesContactWordSettings.provider

        guard NotesContactWordSettings.wordInputEnabled else {
            state = .idle
            return
        }
        guard NotesContactWordSettings.hasWordEndpoint else {
            if context == .test { fail(NotesContactWordSettings.setupHint) }
            state = .idle
            return
        }

        if provider == .card {
            state = .watching
            dlog("[NOTES-WORD] ▶︎ start (\(context == .perform ? "perform" : "test")) · Card line 3 on volume scan")
            return
        }
        if provider == .voice {
            state = .watching
            dlog("[NOTES-WORD] ▶︎ start · Voice AI prompt for Notes chip (shared mic with Song = Voice)")
            return
        }

        state = .connecting
        dlog("[NOTES-WORD] ▶︎ start · \(NotesContactWordSettings.summary())")
        let timer = Timer(timeInterval: WordApiSettings.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    func stopTest() {
        guard isActive else { return }
        generation += 1
        stopPolling()
        state = .idle
        dlog("[NOTES-WORD] ■ test stopped")
    }

    func ingestVoiceWord(_ rawWord: String) {
        guard NotesContactWordSettings.wordInputEnabled else { return }
        guard provider == .voice else { return }
        ingestLockedWord(rawWord, source: "voice")
    }

    func ingestCardScanWord(_ rawWord: String) {
        guard NotesContactWordSettings.wordInputEnabled else { return }
        guard provider == .card else { return }
        ingestLockedWord(rawWord, source: "card")
    }

    private func ingestLockedWord(_ rawWord: String, source: String) {
        guard context == .perform || context == .test else { return }
        let label = rawWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return }
        guard state != .locked else { return }

        let reading = WordReading(count: nil, receiveCount: nil, word: label, raw: "\(source):«\(label)»")
        lastReading = reading
        lockedReading = reading
        state = .locked
        dlog("[NOTES-WORD] 🔒 \(source) · «\(label)»")
        if context == .perform {
            PerformLogReporter.logRecognition(.notesContact, value: label, via: Self.recognitionVia(source: source))
            SpectatorWordContactService.applyContactNoteFromSettings(reason: "notes-\(source)")
        }
    }

    func reset(reason: String) {
        let had = state != .idle || lastReading != nil
        generation += 1
        stopPolling()
        clearState()
        if had { dlog("[NOTES-WORD] ↺ reset (\(reason))") }
    }

    private func tick() {
        guard timer != nil, !isRefreshing else { return }
        isRefreshing = true
        let gen = generation
        provider = NotesContactWordSettings.provider
        let t0 = CACurrentMediaTime()
        Task { [weak self] in
            let result: Result<WordReading, Error>
            do {
                result = .success(try await NotesContactWordClient.fetch())
            } catch {
                result = .failure(error)
            }
            guard let self else { return }
            self.isRefreshing = false
            guard gen == self.generation else { return }
            self.handle(result, ms: PreviewService.ms(since: t0))
        }
    }

    private func handle(_ result: Result<WordReading, Error>, ms: Int) {
        pollCount += 1
        switch result {
        case .failure(let error):
            consecutiveErrors += 1
            lastError = error.localizedDescription
        case .success(let reading):
            consecutiveErrors = 0
            lastError = nil
            lastReading = reading
            if context == .perform {
                handlePerformPoll(reading, ms: ms)
            } else {
                handleTestPoll(reading, ms: ms)
            }
        }
    }

    private func handlePerformPoll(_ reading: WordReading, ms: Int) {
        guard reading.hasWord else { return }
        let label = reading.label
        let priorPoll = previousPollReading
        previousPollReading = reading

        if baseline == nil {
            baseline = reading
            lastAppliedLabel = label
            state = .watching
            dlog("[NOTES-WORD] baseline «\(label)» (\(ms) ms)")
            return
        }

        let textChanged = lastAppliedLabel.map { !ApiJSON.sameText($0, label) } ?? true
        guard textChanged else { return }

        lastAppliedLabel = label
        lockedReading = reading
        state = .locked
        dlog("[NOTES-WORD] 🔒 «\(label)» poll #\(pollCount)")
        PerformLogReporter.logRecognition(.notesContact, value: label, via: NotesContactWordSettings.provider.title)
        SpectatorWordContactService.applyContactNoteFromSettings(reason: "notes-word locked")
        _ = priorPoll
    }

    private func handleTestPoll(_ reading: WordReading, ms: Int) {
        guard let base = baseline else {
            baseline = reading
            previousPollReading = reading
            state = .watching
            return
        }
        let prior = previousPollReading
        previousPollReading = reading
        guard reading.shouldLockPerformWord(comparedTo: base, previousPoll: prior) else { return }
        lockedReading = reading
        state = .locked
        dlog("[NOTES-WORD] 🔒 test lock «\(reading.label)»")
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    private func clearState() {
        state = .idle
        baseline = nil
        lastReading = nil
        lockedReading = nil
        lastError = nil
        consecutiveErrors = 0
        pollCount = 0
        previousPollReading = nil
        lastAppliedLabel = nil
    }

    private static func recognitionVia(source: String) -> String {
        switch source {
        case "voice": return "Voice AI"
        case "card": return "Camera OCR · line 3"
        default: return NotesContactWordSettings.provider.title
        }
    }

    private func fail(_ message: String) {
        state = .failed(message)
        dlog("✗ [NOTES-WORD] \(message)")
    }
}
