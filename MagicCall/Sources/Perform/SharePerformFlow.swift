import UIKit

/// Share Ringtone performance: black screen → (AI Voice listens and locks) → Share sheet opens
/// by itself → performer taps “Use as Ringtone” → the app goes Home by itself (or one tap on the
/// black screen as a fallback).
@MainActor
final class SharePerformFlow: ObservableObject {
    static let shared = SharePerformFlow()

    static let tapToHomeKey = "share.tapToHome"
    static var tapToHome: Bool { bool(tapToHomeKey) }

    static let autoHomeKey = "share.autoHomeAfterShare"
    static var autoHome: Bool { bool(autoHomeKey) }

    private static func bool(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil ? true : UserDefaults.standard.bool(forKey: key)
    }

    enum Step: String {
        case idle, listening, preparing, sharing, shareCancelled, waitingForTap, wentHome
    }

    @Published private(set) var step: Step = .idle
    var isActive: Bool { step != .idle }

    private var observers: [NSObjectProtocol] = []
    private var shareOpenedAt: Date?
    /// Set when “Use as Ringtone” completes: iOS may then bring Settings → Ringtone to the front,
    /// so the next time the app becomes active it goes Home again instead of showing anything.
    private var pendingHomeAfterRingtone = false
    private var shareCompletedAt: Date?
    private var lastHomeAt: Date?
    /// A Settings detour after “Use as Ringtone” is short; later returns are a new performance.
    private static let pendingHomeWindow: TimeInterval = 90

    private init() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { SharePerformFlow.shared.appDidBecomeActive() }
        })
        observers.append(nc.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { SharePerformFlow.shared.appWillResignActive() }
        })
        observers.append(nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { SharePerformFlow.shared.appWillEnterForeground() }
        })
    }

    func start(withVoice: Bool) {
        let model = AppModel.shared
        step = withVoice ? .listening : .preparing
        model.phase = .stage
        UIApplication.shared.isIdleTimerDisabled = true
        dlog("[SHARE PERFORM] 1 · black screen · input=\(withVoice ? "AI Voice" : "Manual") · song=\(model.selected.map { "\($0.title) — \($0.artist)" } ?? "none yet")")
        if withVoice {
            Task { await VoiceSongSession.shared.start(context: .perform) }
        } else {
            Task { await openShare() }
        }
    }

    func voiceLocked() {
        guard step == .listening else { return }
        step = .preparing
        dlog("[SHARE PERFORM] 2 · song locked → preparing ringtone")
        Task { await openShare() }
    }

    func handleTap() {
        switch step {
        case .waitingForTap, .wentHome:
            goHome(reason: "tap")
        case .shareCancelled:
            dlog("[SHARE PERFORM] tap → re-opening Share sheet")
            step = .preparing
            Task { await openShare() }
        case .sharing where UIApplication.mcKeyWindow?.rootViewController?.presentedViewController == nil:
            dlog("[SHARE PERFORM] share closed (no callback) → tap counts")
            goHome(reason: "tap (no callback)")
        default:
            dlog("[SHARE PERFORM] tap ignored at step \(step.rawValue)")
        }
    }

    func reset() {
        guard step != .idle else { return }
        dlog("[SHARE PERFORM] ↺ reset from step \(step.rawValue)")
        step = .idle
        shareOpenedAt = nil
        shareCompletedAt = nil
        lastHomeAt = nil
        pendingHomeAfterRingtone = false
        RingtoneSharePresenter.onNextCompletion = nil
    }

    // MARK: Steps

    private func openShare() async {
        let model = AppModel.shared
        let voice = VoiceSongSession.shared
        if voice.isActive { voice.reset(reason: "share sheet") }
        VoiceAudioSession.recordCategoryActive = false
        VoiceAudioSession.deactivateIfIdle()
        dlog("[SHARE PERFORM] mic fully stopped before Share (voice state=\(voice.state))")

        guard model.loadState == .ready else {
            dlog("✗ [SHARE PERFORM] no song ready — nothing to share")
            step = .waitingForTap
            return
        }
        var waited = 0
        while Prefs.autoStageRingtone, !model.ringtoneStaged, waited < 40 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            waited += 1
        }
        guard step == .preparing else { return }
        step = .sharing
        shareOpenedAt = Date()
        RingtoneSharePresenter.onNextCompletion = { activity, completed in
            MainActor.assumeIsolated { SharePerformFlow.shared.shareFinished(activity: activity, completed: completed) }
        }
        dlog("[SHARE PERFORM] 3 · opening Share sheet (ringtone file ready=\(model.ringtoneStaged), waited \(waited * 100) ms)")
        await model.performShareRingtone()
    }

    private func shareFinished(activity: String?, completed: Bool) {
        guard step == .sharing else { return }
        let secs = shareOpenedAt.map { String(format: "%.1f", Date().timeIntervalSince($0)) } ?? "?"
        dlog("[SHARE PERFORM] 4 · Share closed after \(secs) s · activity=\(activity ?? "none") completed=\(completed) · app=\(Self.appState())")
        guard completed else {
            step = .shareCancelled
            dlog("[SHARE PERFORM] not completed → black screen; tap to open Share again")
            return
        }
        step = .waitingForTap
        shareCompletedAt = Date()
        let looksLikeRingtone = (activity ?? "").lowercased().contains("ringtone")
        dlog("[SHARE PERFORM] completed · ringtone activity=\(looksLikeRingtone)")
        guard Self.autoHome else {
            dlog("[SHARE PERFORM] auto-Home is off → tap the black screen to go Home")
            return
        }
        pendingHomeAfterRingtone = true
        goHome(reason: "auto, immediately after Use as Ringtone")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            MainActor.assumeIsolated { SharePerformFlow.shared.retryHome(reason: "auto +0.3 s") }
        }
    }

    /// Repeats the Home jump while “Use as Ringtone” may still be pulling Settings forward.
    private func retryHome(reason: String) {
        guard pendingHomeAfterRingtone, step == .waitingForTap || step == .wentHome else { return }
        guard UIApplication.shared.applicationState == .active else {
            dlog("[SHARE PERFORM] \(reason): app not in front (\(Self.appState())) — will go Home when it becomes active again")
            return
        }
        goHome(reason: reason)
    }

    private func appDidBecomeActive() {
        guard pendingHomeAfterRingtone, step == .waitingForTap || step == .wentHome else { return }
        if let done = shareCompletedAt, Date().timeIntervalSince(done) > Self.pendingHomeWindow {
            pendingHomeAfterRingtone = false
            dlog("[SHARE PERFORM] back after \(Int(Date().timeIntervalSince(done))) s — Home no longer pending → reset for next performance")
            AppModel.shared.disarm()
            return
        }
        dlog("[SHARE PERFORM] app active again after Use as Ringtone (maybe back from Settings) → Home")
        pendingHomeAfterRingtone = false
        goHome(reason: "became active after Use as Ringtone")
    }

    private static func appState() -> String {
        switch UIApplication.shared.applicationState {
        case .active: return "active"
        case .inactive: return "inactive"
        case .background: return "background"
        @unknown default: return "?"
        }
    }

    private func goHome(reason: String) {
        guard Self.tapToHome else {
            dlog("[SHARE PERFORM] tap-to-Home is off in Advanced — swipe up to go Home")
            return
        }
        let selector = NSSelectorFromString("suspend")
        guard UIApplication.shared.responds(to: selector) else {
            dlog("✗ [SHARE PERFORM] suspend not available — swipe up to go Home")
            return
        }
        if let last = lastHomeAt, Date().timeIntervalSince(last) < 0.5 {
            dlog("[SHARE PERFORM] \(reason): Home already requested \(Int(Date().timeIntervalSince(last) * 1000)) ms ago — skip")
            return
        }
        lastHomeAt = Date()
        step = .wentHome
        dlog("[SHARE PERFORM] 5 · \(reason) → Home Screen (app=\(Self.appState()))", sync: true)
        _ = UIApplication.shared.perform(selector)
    }

    private func appWillResignActive() {
        if step == .sharing {
            dlog("[SHARE PERFORM] ⚠️ app left the foreground while Share was open — iOS may have shown a confirmation or opened Settings after “Use as Ringtone”")
        }
        if pendingHomeAfterRingtone, let done = shareCompletedAt, Date().timeIntervalSince(done) < 3 {
            dlog("[SHARE PERFORM] willResignActive \(String(format: "%.2f", Date().timeIntervalSince(done))) s after Use as Ringtone (iOS opening Settings?) → Home")
            goHome(reason: "willResignActive after Use as Ringtone")
        }
    }

    private func appWillEnterForeground() {
        switch step {
        case .wentHome where pendingHomeAfterRingtone:
            dlog("[SHARE PERFORM] back in app with Home still pending (likely from Settings) → keep black screen")
        case .wentHome:
            dlog("[SHARE PERFORM] back in app after Home → reset for next performance")
            AppModel.shared.disarm()
        case .sharing, .shareCancelled, .waitingForTap:
            dlog("[SHARE PERFORM] back in app at step \(step.rawValue)")
        default:
            break
        }
    }
}
