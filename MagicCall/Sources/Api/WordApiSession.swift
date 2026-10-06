import Foundation
import QuartzCore

/// Polls Inject / Elips / Custom Word API every 2 s during Perform. Uses the latest label; lock + cues when the response changes.
@MainActor
final class WordApiSession: ObservableObject {
    static let shared = WordApiSession()

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
    @Published private(set) var provider: WordApiSettings.Provider = .inject
    @Published private(set) var baseline: WordReading?
    @Published private(set) var lastReading: WordReading?
    @Published private(set) var lockedReading: WordReading?
    @Published private(set) var lastError: String?
    @Published private(set) var consecutiveErrors = 0
    @Published private(set) var pollCount = 0

    var isActive: Bool {
        switch state {
        case .connecting, .watching, .locked: return timer != nil
        default: return false
        }
    }

    var isStruggling: Bool { consecutiveErrors >= 3 }

    private var timer: Timer?
    private var isRefreshing = false
    private var generation = 0
    private var unchangedCountPolls = 0
    private var loggedStalePollWarning = false
    private var previousPollReading: WordReading?
    /// Last label written to Call Directory this Perform (poll-to-poll text compare).
    private var lastAppliedLabel: String?

    private init() {}

    func start(context: Context) {
        stopPolling()
        clearState()
        generation += 1
        self.context = context
        provider = WordApiSettings.provider
        if context == .perform, !WordApiSettings.callerLabelEnabled {
            state = .idle
            return
        }
        guard WordApiSettings.hasWordEndpoint else {
            fail(WordApiSettings.setupHint)
            return
        }
        if context == .test, !WordApiSettings.callerLabelEnabled {
            fail("Turn on caller label on the Word API card first")
            return
        }
        state = .connecting
        WordApiClient.resetPerformFetchDiagnostics()
        dlog("[WORD] ▶︎ start (\(context == .perform ? "perform" : "test")) · \(WordApiSettings.summary())")
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
        dlog("[WORD] ■ test stopped after \(pollCount) polls")
    }

    func reset(reason: String) {
        let had = state != .idle || lastReading != nil
        generation += 1
        stopPolling()
        clearState()
        if WordApiSettings.callerLabelEnabled {
            CallerLabelStore.clearLockedLabel()
            CallDirectorySync.reloadExtensions(reason: "word reset (\(reason))")
        }
        if had { dlog("[WORD] ↺ reset (\(reason))") }
    }

    private func tick() {
        guard timer != nil, !isRefreshing else { return }
        isRefreshing = true
        let gen = generation
        provider = WordApiSettings.provider
        let provider = self.provider
        let upcomingPoll = pollCount + 1
        let performDiag = context == .perform ? WordFetchDiagnostics(pollNumber: upcomingPoll) : nil
        let t0 = CACurrentMediaTime()
        Task { [weak self] in
            let result: Result<WordReading, Error>
            do {
                result = .success(try await WordApiClient.fetch(provider, performDiagnostics: performDiag))
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
            if context == .perform, consecutiveErrors == 3 {
                PerformUserLog.shared.logConnectionIssue("Word API offline · retrying")
            }
            if consecutiveErrors == 1 || consecutiveErrors % 10 == 0 {
                dlog("✗ [WORD] poll #\(pollCount) failed ×\(consecutiveErrors) (\(ms) ms): \(error.localizedDescription)")
            }
        case .success(let reading):
            if consecutiveErrors > 0 { dlog("[WORD] reachable again after \(consecutiveErrors) failed polls") }
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

    /// Perform: every 2 s — if the **text** from the API changed vs last applied, update caller label (+ cues after baseline).
    private func handlePerformPoll(_ reading: WordReading, ms: Int) {
        guard reading.hasWord else {
            dlog("[WORD] poll #\(pollCount) (\(provider.title)) sin texto (\(ms) ms) · \(reading.raw.prefix(160))")
            previousPollReading = reading
            return
        }
        let label = reading.label
        let priorPoll = previousPollReading
        previousPollReading = reading

        if baseline == nil {
            baseline = reading
            lastAppliedLabel = label
            state = .watching
            unchangedCountPolls = 0
            loggedStalePollWarning = false
            pushCallerLabel(label, reason: "start")
            dlog("[WORD] start (\(ms) ms) · \(provider.title) «\(label)»")
            return
        }

        let textChanged = lastAppliedLabel.map { !ApiJSON.sameText($0, label) } ?? true
        let pollDelta = priorPoll.map { reading.pollDelta(comparedTo: $0) } ?? false
        dlog("[WORD] poll #\(pollCount) · \(provider.title) «\(label)» textChanged=\(textChanged) pollDelta=\(pollDelta) (\(ms) ms)")

        trackStalePolls(reading, baseline: baseline!)

        guard textChanged else { return }

        pushCallerLabel(label, reason: "text-changed")
        lastAppliedLabel = label
        lockedReading = reading
        state = .locked
        let buzzOn = PerformanceCues.vibrateOnLock
        dlog("[WORD] 🔒 «\(label)» poll #\(pollCount) · label updated · buzz=\(buzzOn)")
        PerformanceCues.wordLocked(source: "Word API", label: label)
    }

    private func handleTestPoll(_ reading: WordReading, ms: Int) {
        guard let base = baseline else {
            baseline = reading
            previousPollReading = reading
            state = .watching
            dlog("[WORD] baseline (\(ms) ms) · \(provider.title) «\(reading.label)»")
            return
        }
        let prior = previousPollReading
        previousPollReading = reading
        guard reading.shouldLockPerformWord(comparedTo: base, previousPoll: prior) else { return }
        lock(reading)
    }

    private func trackStalePolls(_ reading: WordReading, baseline: WordReading) {
        let snapshotUnchanged = reading.matchesSnapshot(of: baseline)
        if snapshotUnchanged {
            unchangedCountPolls += 1
        } else {
            unchangedCountPolls = 0
            loggedStalePollWarning = false
        }
        if unchangedCountPolls >= 6, !loggedStalePollWarning {
            dlog("[WORD] ⚠ \(stalePerformHint(provider: provider, baseline: baseline))")
            loggedStalePollWarning = true
        }
    }

    private func pushCallerLabel(_ label: String, reason: String) {
        guard WordApiSettings.callerLabelEnabled else { return }
        CallerLabelStore.applyLockedLabel(label)
        CallDirectorySync.refreshIdentificationNumbers()
        CallDirectorySync.reloadExtensions(reason: "word \(reason)")
        dlog("[WORD] etiqueta → «\(label)» (\(reason))")
    }

    private func lock(_ reading: WordReading) {
        lockedReading = reading
        state = .locked
        let buzzOn = PerformanceCues.vibrateOnLock
        dlog("[WORD] 🔒 lock “\(reading.label)” after \(pollCount) polls · callerLabelEnabled=\(WordApiSettings.callerLabelEnabled) buzzOn=\(buzzOn) · polling continues")
        if context == .perform {
            PerformanceCues.wordLocked(source: "Word API", label: reading.label)
        }
        guard WordApiSettings.callerLabelEnabled else { return }
        CallerLabelStore.applyLockedLabel(reading.label)
        CallDirectorySync.refreshIdentificationNumbers()
        CallDirectorySync.reloadExtensions(reason: "word locked")
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
        isRefreshing = false
    }

    private func clearState() {
        state = .idle
        baseline = nil
        lastReading = nil
        lockedReading = nil
        lastError = nil
        consecutiveErrors = 0
        pollCount = 0
        unchangedCountPolls = 0
        loggedStalePollWarning = false
        previousPollReading = nil
        lastAppliedLabel = nil
        WordApiClient.resetPerformFetchDiagnostics()
    }

    private func stalePerformHint(provider: WordApiSettings.Provider, baseline: WordReading) -> String {
        let word = baseline.label
        switch provider {
        case .inject:
            let c = baseline.count.map(String.init) ?? "–"
            let r = baseline.receiveCount.map(String.init) ?? "–"
            return "Inject unchanged (\(c)/\(r)) «\(word)»"
        case .elips:
            return "Elips unchanged «\(word)»"
        case .custom:
            return "Custom API unchanged «\(word)»"
        }
    }

    private func fail(_ message: String) {
        stopPolling()
        state = .failed(message)
        if context == .perform {
            PerformUserLog.shared.log("Word API · \(message)")
        }
        dlog("✗ [WORD] \(message)")
    }
}
