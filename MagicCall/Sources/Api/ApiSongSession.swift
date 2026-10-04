import Foundation
import QuartzCore
import UIKit

/// Polls the active API integration every `ApiSettings.pollInterval` seconds. The first reading
/// after Perform is the baseline (whatever was searched before); the next change is the
/// spectator's search: it is loaded with the same lookup as AI Voice and locked once ready.
@MainActor
final class ApiSongSession: ObservableObject {
    static let shared = ApiSongSession()

    enum Context { case perform, test }

    enum State: Equatable {
        case idle
        case connecting
        case watching
        case loading(String)
        case locked
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var context: Context = .test
    @Published private(set) var provider: ApiSettings.Provider = .inject
    @Published private(set) var baseline: ApiReading?
    @Published private(set) var lastReading: ApiReading?
    @Published private(set) var lockedReading: ApiReading?
    @Published private(set) var notFound: String?
    @Published private(set) var lastError: String?
    @Published private(set) var consecutiveErrors = 0
    @Published private(set) var pollCount = 0

    var isActive: Bool {
        switch state {
        case .connecting, .watching, .loading: return true
        default: return false
        }
    }

    /// Network trouble worth showing (a single dropped request is not).
    var isStruggling: Bool { consecutiveErrors >= 3 }

    private var timer: Timer?
    private var isRefreshing = false
    private var generation = 0

    private init() {}

    // MARK: Lifecycle

    func start(context: Context) {
        stopPolling()
        clearState()
        generation += 1
        self.context = context
        provider = ApiSettings.provider
        guard ApiSettings.isConfigured else {
            fail(ApiSettings.setupHint)
            return
        }
        state = .connecting
        dlog("[API] ▶︎ start (\(context == .perform ? "perform" : "test")) · \(ApiSettings.summary())")
        let timer = Timer(timeInterval: ApiSettings.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    /// Test "Stop": stops polling, keeps the last reading on screen.
    func stopTest() {
        guard isActive else { return }
        generation += 1
        stopPolling()
        state = .idle
        dlog("[API] ■ test stopped after \(pollCount) polls")
    }

    /// Clears baseline, readings and the locked song (called when leaving or re-entering Perform).
    func reset(reason: String) {
        let had = state != .idle || lastReading != nil
        generation += 1
        stopPolling()
        clearState()
        if had { dlog("[API] ↺ reset (\(reason))") }
    }

    /// A call (or manual trigger) arrived before the spectator's search was found: stop polling.
    func callArrived(source: String) {
        guard isActive else { return }
        dlog("[API] call/trigger (\(source)) before a song locked (state=\(state)) — polling stopped")
        generation += 1
        stopPolling()
        state = .idle
    }

    // MARK: Polling

    private func tick() {
        guard timer != nil, !isRefreshing else { return }
        if case .loading = state { return }
        isRefreshing = true
        let gen = generation
        let provider = self.provider
        let t0 = CACurrentMediaTime()
        Task { [weak self] in
            let result: Result<ApiReading, Error>
            do {
                result = .success(try await ApiSongClient.fetch(provider))
            } catch {
                result = .failure(error)
            }
            guard let self else { return }
            self.isRefreshing = false
            guard gen == self.generation else { return }
            self.handle(result, ms: PreviewService.ms(since: t0))
        }
    }

    private func handle(_ result: Result<ApiReading, Error>, ms: Int) {
        pollCount += 1
        switch result {
        case .failure(let error):
            consecutiveErrors += 1
            lastError = error.localizedDescription
            if consecutiveErrors == 1 || consecutiveErrors % 10 == 0 {
                dlog("✗ [API] poll #\(pollCount) failed ×\(consecutiveErrors) (\(ms) ms): \(error.localizedDescription)")
            }
        case .success(let reading):
            if consecutiveErrors > 0 { dlog("[API] reachable again after \(consecutiveErrors) failed polls") }
            consecutiveErrors = 0
            lastError = nil
            lastReading = reading
            if case .loading = state { return }
            guard let base = baseline else {
                baseline = reading
                state = .watching
                dlog("[API] baseline (\(ms) ms): count=\(reading.count.map(String.init) ?? "–") “\(reading.label)” — waiting for a new search")
                return
            }
            guard reading.isNewSearch(comparedTo: base) else { return }
            dlog("[API] ★ new search (\(ms) ms): count \(base.count.map(String.init) ?? "–")→\(reading.count.map(String.init) ?? "–") · “\(base.label)” → “\(reading.label)”")
            baseline = reading
            Task { await load(reading) }
        }
    }

    // MARK: Load & lock

    private func load(_ reading: ApiReading) async {
        let gen = generation
        state = .loading(reading.label)
        notFound = nil
        AppModel.shared.dropPreviewForNewLookup()
        let t0 = CACurrentMediaTime()
        let ok = await AppModel.shared.prepareApiQuery(reading.searchQuery)
        guard gen == generation else { return }
        let track = AppModel.shared.selected.map { "\($0.title) — \($0.artist)" } ?? "?"
        dlog("[API] lookup “\(reading.searchQuery)” → \(ok ? "ready: \(track)" : "not found") (\(PreviewService.ms(since: t0)) ms)")
        if ok {
            lock(reading)
        } else {
            notFound = reading.label
            state = .watching
        }
    }

    private func lock(_ reading: ApiReading) {
        stopPolling()
        lockedReading = reading
        state = .locked
        dlog("[API] 🔒 locked “\(reading.label)” after \(pollCount) polls")
        if context == .perform { PerformanceCues.songLocked(source: "API") }
        AppModel.shared.apiSongLocked(context: context)
    }

    // MARK: Helpers

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
        notFound = nil
        lastError = nil
        consecutiveErrors = 0
        pollCount = 0
    }

    private func fail(_ message: String) {
        stopPolling()
        state = .failed(message)
        dlog("✗ [API] \(message)")
    }
}
