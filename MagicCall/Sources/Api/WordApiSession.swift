import Foundation
import QuartzCore

/// Polls the Word API during Perform. First reading = baseline; next change = spectator word → locked → Call Directory.
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
        case .connecting, .watching: return true
        default: return false
        }
    }

    var isStruggling: Bool { consecutiveErrors >= 3 }

    private var timer: Timer?
    private var isRefreshing = false
    private var generation = 0
    private var unchangedCountPolls = 0
    private var loggedStaleInjectCount = false
    private var lastUnchangedPerformUserLogAt: Date?

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
        lastUnchangedPerformUserLogAt = nil
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
                PerformUserLog.shared.logConnectionIssue("Word API sin conexión · reintentando")
            }
            if consecutiveErrors == 1 || consecutiveErrors % 10 == 0 {
                dlog("✗ [WORD] poll #\(pollCount) failed ×\(consecutiveErrors) (\(ms) ms): \(error.localizedDescription)")
            }
        case .success(let reading):
            if consecutiveErrors > 0 { dlog("[WORD] reachable again after \(consecutiveErrors) failed polls") }
            consecutiveErrors = 0
            lastError = nil
            lastReading = reading
            guard let base = baseline else {
                baseline = reading
                state = .watching
                unchangedCountPolls = 0
                loggedStaleInjectCount = false
                dlog("[WORD] baseline (\(ms) ms): count=\(reading.count.map(String.init) ?? "–") receive=\(reading.receiveCount.map(String.init) ?? "–") “\(reading.label)” — waiting for change")
                if context == .perform {
                    let integration = WordApiSettings.provider.title
                    PerformUserLog.shared.log(
                        "Word API: baseline «\(reading.label)» — change \(integration) during show for lock (3 short buzzes)."
                    )
                }
                return
            }
            if context == .perform, case .watching = state {
                let baseCount = base.count.map(String.init) ?? "–"
                let baseReceive = base.receiveCount.map(String.init) ?? "–"
                dlog("[WORD] poll #\(pollCount) watching (\(ms) ms) baseline count=\(baseCount) receive=\(baseReceive) word=«\(base.label)» · now count=\(reading.count.map(String.init) ?? "–") receive=\(reading.receiveCount.map(String.init) ?? "–") word=«\(reading.label)» isNew=\(reading.isNewWord(comparedTo: base))")
            }
            let snapshotUnchanged = reading.count == base.count
                && reading.receiveCount == base.receiveCount
                && ApiJSON.sameText(reading.word, base.word)
            if snapshotUnchanged {
                unchangedCountPolls += 1
            } else {
                unchangedCountPolls = 0
                loggedStaleInjectCount = false
            }
            if context == .perform, provider == .inject, unchangedCountPolls >= 6, !loggedStaleInjectCount {
                let c = base.count.map(String.init) ?? "–"
                let r = base.receiveCount.map(String.init) ?? "–"
                PerformUserLog.shared.log("Inject still count \(c) receive \(r) — submit new word on 11z.co")
                loggedStaleInjectCount = true
            }
            guard reading.isNewWord(comparedTo: base) else {
                logUnchangedPoll(reading, baseline: base, ms: ms)
                return
            }
            let oldCount = base.count.map(String.init) ?? "–"
            let newCount = reading.count.map(String.init) ?? "–"
            let oldReceive = base.receiveCount.map(String.init) ?? "–"
            let newReceive = reading.receiveCount.map(String.init) ?? "–"
            dlog("[WORD] ★ isNewWord poll #\(pollCount) (\(ms) ms): count \(oldCount)→\(newCount) receive \(oldReceive)→\(newReceive) “\(base.label)”→“\(reading.label)”")
            baseline = reading
            lock(reading)
        }
    }

    private func logUnchangedPoll(_ reading: WordReading, baseline base: WordReading, ms: Int) {
        let baseCount = base.count.map(String.init) ?? "–"
        let nowCount = reading.count.map(String.init) ?? "–"
        let slightlyDifferent = reading.count != base.count
            || reading.receiveCount != base.receiveCount
            || reading.word != base.word
        let periodic = pollCount % 5 == 0
        guard periodic || slightlyDifferent else { return }
        let reason = reading.unchangedVsBaselineReason(comparedTo: base)
        dlog("[WORD] poll #\(pollCount) unchanged vs baseline count=\(baseCount) word=«\(base.label)» (\(ms) ms; now count=\(nowCount) word=«\(reading.label)» · \(reason))")
        guard context == .perform else { return }
        let now = Date()
        if let last = lastUnchangedPerformUserLogAt, now.timeIntervalSince(last) < 12 { return }
        lastUnchangedPerformUserLogAt = now
        PerformUserLog.shared.log("Word API: esperando cambio · «\(reading.label)» (\(reason))")
    }

    private func lock(_ reading: WordReading) {
        stopPolling()
        lockedReading = reading
        state = .locked
        let wordDotEnabled = UserDefaults.standard.bool(forKey: PerformanceCues.Key.wordDotEnabled)
        let dotShouldShow = wordDotEnabled
            && WordApiSettings.callerLabelEnabled
            && context == .perform
        let buzzOn = PerformanceCues.vibrateOnLock
        dlog("[WORD] 🔒 lock “\(reading.label)” after \(pollCount) polls · callerLabelEnabled=\(WordApiSettings.callerLabelEnabled) wordDotEnabled=\(wordDotEnabled) buzzOn=\(buzzOn) state=locked dotShouldShow=\(dotShouldShow)")
        if context == .perform {
            PerformUserLog.shared.log(
                "Word bloqueada · punto naranja \(dotShouldShow ? "ON" : "OFF") · vibración \(buzzOn ? "3 toques" : "desactivada")"
            )
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
        loggedStaleInjectCount = false
        lastUnchangedPerformUserLogAt = nil
        WordApiClient.resetPerformFetchDiagnostics()
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
