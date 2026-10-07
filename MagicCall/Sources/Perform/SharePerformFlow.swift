import UIKit

/// Share Ringtone performance: black screen → song locks → Share sheet → performer uses
/// “Use as Ringtone”, then leaves Perform manually (Home / swipe down).
@MainActor
final class SharePerformFlow: ObservableObject {
    static let shared = SharePerformFlow()

    static let hapticOnShareKey = "share.hapticOnShare"
    static var hapticOnShare: Bool {
        UserDefaults.standard.object(forKey: hapticOnShareKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: hapticOnShareKey)
    }

    enum Step: String {
        case idle, listening, preparing, sharing, shareCancelled, waitingForTap
    }

    @Published private(set) var step: Step = .idle
    var isActive: Bool { step != .idle }

    private var shareOpenedAt: Date?

    /// Steps where a tap on the stage does something.
    var acceptsStageTap: Bool {
        switch step {
        case .sharing, .shareCancelled, .waitingForTap: return true
        default: return false
        }
    }

    func start(input: VoiceSettings.InputMode) {
        let model = AppModel.shared
        step = input == .manual ? .preparing : .listening
        model.phase = .stage
        AppModel.setScreenAwakeWhileInForeground(true)
        let screen = input == .notes ? "Notes screen" : "black screen"
        dlog("[SHARE PERFORM] 1 · \(screen) · input=\(input.title) · song=\(model.selected.map { "\($0.title) — \($0.artist)" } ?? "none yet")")
        switch input {
        case .aiVoice:
            Task { await VoiceSongSession.shared.start(context: .perform) }
        case .api:
            ApiSongSession.shared.start(context: .perform, liveWatchHandoff: AppModel.shared.pendingApiLiveWatchHandoff)
            AppModel.shared.pendingApiLiveWatchHandoff = nil
        case .notes:
            NotesSongSession.shared.start(context: .perform)
        case .card:
            CardSongSession.shared.start(context: .perform)
        case .manual:
            Task { await openShare() }
        }
    }

    func songLocked() {
        guard step == .listening else { return }
        step = .preparing
        dlog("[SHARE PERFORM] 2 · song locked → preparing ringtone")
        Task { await openShare() }
    }

    func handleTap() {
        switch step {
        case .waitingForTap:
            dlog("[SHARE PERFORM] tap → leave Perform (two-finger swipe also works)")
            AppModel.shared.disarm()
        case .shareCancelled:
            dlog("[SHARE PERFORM] tap → re-opening Share sheet")
            step = .preparing
            Task { await openShare() }
        case .sharing where UIApplication.mcKeyWindow?.rootViewController?.presentedViewController == nil:
            dlog("[SHARE PERFORM] share closed (no callback) → leave Perform")
            AppModel.shared.disarm()
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
        if ApiSongSession.shared.isActive { ApiSongSession.shared.stopTest() }
        if CardSongSession.shared.isActive { CardSongSession.shared.reset(reason: "share sheet") }
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
        dlog("[SHARE PERFORM] 4 · Share closed after \(secs) s · activity=\(activity ?? "none") completed=\(completed)")
        guard completed else {
            step = .shareCancelled
            dlog("[SHARE PERFORM] not completed → black screen; tap to open Share again")
            return
        }
        step = .waitingForTap
        if Self.hapticOnShare {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.8)
            dlog("[SHARE PERFORM] haptic cue: ringtone added")
        }
        dlog("[SHARE PERFORM] done — press Home on the iPhone, or tap the black screen / swipe down to leave Perform")
    }
}
