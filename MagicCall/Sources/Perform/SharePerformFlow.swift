import UIKit

/// Share Ringtone performance: black screen → (AI Voice listens and locks) → Share sheet opens
/// by itself → performer taps “Use as Ringtone” → one tap on the black screen goes Home.
@MainActor
final class SharePerformFlow: ObservableObject {
    static let shared = SharePerformFlow()

    static let tapToHomeKey = "share.tapToHome"
    static var tapToHome: Bool {
        UserDefaults.standard.object(forKey: tapToHomeKey) == nil ? true : UserDefaults.standard.bool(forKey: tapToHomeKey)
    }

    enum Step: String {
        case idle, listening, preparing, sharing, waitingForTap, wentHome
    }

    @Published private(set) var step: Step = .idle
    var isActive: Bool { step != .idle }

    private var observers: [NSObjectProtocol] = []
    private var shareOpenedAt: Date?

    private init() {
        let nc = NotificationCenter.default
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
        case .waitingForTap:
            goHome()
        case .sharing where UIApplication.mcKeyWindow?.rootViewController?.presentedViewController == nil:
            dlog("[SHARE PERFORM] share closed (no callback) → tap counts")
            goHome()
        default:
            dlog("[SHARE PERFORM] tap ignored at step \(step.rawValue)")
        }
    }

    func reset() {
        guard step != .idle else { return }
        dlog("[SHARE PERFORM] ↺ reset from step \(step.rawValue)")
        step = .idle
        shareOpenedAt = nil
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
        dlog("[SHARE PERFORM] 4 · Share closed after \(secs) s · activity=\(activity ?? "none") completed=\(completed) · black screen, waiting for tap")
        step = .waitingForTap
    }

    private func goHome() {
        guard Self.tapToHome else {
            dlog("[SHARE PERFORM] tap-to-Home is off in Advanced — swipe up to go Home")
            return
        }
        let selector = NSSelectorFromString("suspend")
        guard UIApplication.shared.responds(to: selector) else {
            dlog("✗ [SHARE PERFORM] suspend not available — swipe up to go Home")
            return
        }
        step = .wentHome
        dlog("[SHARE PERFORM] 5 · tap → Home Screen", sync: true)
        _ = UIApplication.shared.perform(selector)
    }

    private func appWillResignActive() {
        if step == .sharing {
            dlog("[SHARE PERFORM] ⚠️ app left the foreground while Share was open — iOS may have shown a confirmation or opened Settings after “Use as Ringtone”")
        }
    }

    private func appWillEnterForeground() {
        switch step {
        case .wentHome, .waitingForTap:
            dlog("[SHARE PERFORM] back in app after Home (from \(step.rawValue)) → reset for next performance")
            AppModel.shared.disarm()
        case .sharing:
            dlog("[SHARE PERFORM] back in app at step \(step.rawValue)")
        default:
            break
        }
    }
}
