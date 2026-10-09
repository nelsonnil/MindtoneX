import AVFoundation
import QuartzCore

/// Perform with Interference ringtone: the incoming call (or a manual trigger) starts the ringtone loop and
/// the front camera → open hand → interference → song 1. With Spectators = 2 and song 2 ready, a second
/// hand (after `InterferenceSettings.secondHandCooldown`, previous hand gone) → interference audio 2 → song 2.
/// Owned by `AppModel`; the normal `RingtoneAudioEngine` stays in silent hot standby meanwhile.
@MainActor
final class InterferenceShowController: ObservableObject {
    enum Phase: String {
        case idle
        case ringing
        case morph1
        case song1
        case morph2
        case song2
    }

    struct Song {
        let data: Data
        let fileTypeHint: String
        let title: String
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var waitingForSecondHand = false

    /// iOS stopped the engine (configuration change) or a hand arrived while it was stopped:
    /// `AppModel` retriggers, which calls `reassert`.
    var onEngineLost: (@MainActor (String) -> Void)?

    private var audio: InterferenceAudioEngine?
    private let detector = HandGestureDetector()
    private var runID = 0
    private var ringStartedAt: CFTimeInterval = 0
    private var firstHandAt: CFTimeInterval = 0
    private var hasSecondSong = false
    private var firstSongClean = false
    private var secondHandQueued = false
    private var secondHandSeen = false
    private var secondHandWatchDue = false

    var isActive: Bool { phase != .idle }
    var isRunning: Bool { audio?.isRunning ?? false }
    /// Ringing (first hand) or, with two spectators, song 1 waiting for the second hand.
    var awaitingHand: Bool { phase == .ringing || waitingForSecondHand }

    init() {
        detector.onOpenHand = { [weak self] _ in
            MainActor.assumeIsolated { self?.handSeen(source: "camera") }
        }
        detector.onInterrupted = { [weak self] reason in
            MainActor.assumeIsolated { self?.cameraInterrupted(reason) }
        }
    }

    // MARK: Run

    /// Starts the ringtone for this call. Returns false when the effect cannot run, so the caller can
    /// fall back to the normal ringtone (the song plays straight away, as without interference).
    func start(song1: Song, song2: Song?, configureSession: () throws -> Void) -> Bool {
        stop(reason: "new ring")
        let ringtone = InterferenceSettings.ringtone
        let preset = InterferenceSettings.resolvedPreset(
            storedRaw: UserDefaults.standard.string(forKey: InterferenceSettings.Key.presetID)
        )
        guard let ringtoneURL = InterferenceSettings.bundledAudioURL(named: ringtone.resourceName),
              let interferenceURL = InterferenceSettings.bundledAudioURL(named: preset.resourceName) else {
            PerformUserLog.shared.log("Interference · sound files missing from this build · normal ringtone")
            dlog("[INTERF] perform · missing \(ringtone.resourceName) or \(preset.resourceName) · fallback")
            return false
        }
        guard CardSettings.cameraAuthorized else {
            PerformUserLog.shared.log("Interference · camera not allowed · normal ringtone (iPhone Settings → MindtoneX → Camera)")
            dlog("[INTERF] perform · camera not authorized · fallback")
            return false
        }

        var secondStage: InterferenceAudioEngine.SecondStage?
        if let song2 {
            secondStage = InterferenceAudioEngine.SecondStage(
                interferenceURL: InterferenceSettings.secondHandInterferenceURL ?? interferenceURL,
                songData: song2.data,
                songFileTypeHint: song2.fileTypeHint
            )
        }
        let engine = InterferenceAudioEngine()
        engine.loopSongs = true
        engine.onConfigurationChange = { [weak self] in
            MainActor.assumeIsolated { self?.engineConfigurationChanged() }
        }
        do {
            try configureSession()
            try engine.prepare(
                ringtoneURL: ringtoneURL,
                interferenceURL: interferenceURL,
                songData: song1.data,
                songFileTypeHint: song1.fileTypeHint,
                second: secondStage
            )
            try engine.startRingtone()
        } catch {
            engine.stop()
            PerformUserLog.shared.log("Interference · audio could not start · normal ringtone")
            dlog("[INTERF] perform · start failed: \(RingtoneAudioEngine.describe(error)) · fallback")
            return false
        }

        runID += 1
        audio = engine
        hasSecondSong = secondStage != nil
        firstSongClean = false
        secondHandQueued = false
        secondHandSeen = false
        secondHandWatchDue = false
        waitingForSecondHand = false
        ringStartedAt = CACurrentMediaTime()
        phase = .ringing
        startCamera(requireClearFirst: false)
        let spectators = hasSecondSong ? " · 2 spectators (\(song1.title) / \(song2?.title ?? "?"))" : " · \(song1.title)"
        PerformUserLog.shared.log("Interference · ringing · \(ringtone.title) · waiting for an open hand\(spectators)")
        dlog("[INTERF] perform · ringing · \(ringtone.title) · \(preset.title)\(hasSecondSong ? " → \(InterferenceSettings.secondHandTitle)" : "") · \(engine.snapshot())")
        return true
    }

    /// After iOS stopped the engine (interruption, route change) or on return to the app:
    /// restart it where the effect was and make sure the camera is watching if a hand is still due.
    @discardableResult
    func reassert(reason: String, configureSession: () throws -> Void) -> Bool {
        guard isActive, let audio else { return false }
        do {
            try configureSession()
            try audio.resume()
        } catch {
            dlog("[INTERF] perform · reassert (\(reason)) failed: \(RingtoneAudioEngine.describe(error))")
            return false
        }
        if phase == .ringing {
            startCamera(requireClearFirst: false)
        } else if waitingForSecondHand || (secondHandWatchDue && phase == .song1 && !secondHandSeen) {
            waitingForSecondHand = true
            startCamera(requireClearFirst: true)
        }
        dlog("[INTERF] perform · reasserted (\(reason)) · phase=\(phase.rawValue) · \(audio.snapshot())")
        return audio.isRunning
    }

    /// Back Tap, volume trigger or debug: stands in for the hand the camera has not seen.
    func forceHand(source: String) {
        guard awaitingHand else { return }
        dlog("[INTERF] perform · manual hand (\(source))")
        handSeen(source: source)
    }

    func stop(reason: String) {
        runID += 1
        detector.stop()
        audio?.stop()
        audio = nil
        waitingForSecondHand = false
        secondHandWatchDue = false
        if phase != .idle {
            dlog("[INTERF] perform · stopped (\(reason))")
        }
        phase = .idle
    }

    func snapshot() -> String {
        "phase=\(phase.rawValue) hand2=\(waitingForSecondHand) \(audio?.snapshot() ?? "no engine")"
    }

    /// Stage peek line (performer only).
    var peekStatus: String {
        switch phase {
        case .idle: return "Interference · off"
        case .ringing: return "Ringing · waiting for hand"
        case .morph1: return "Interference → song 1"
        case .song1: return waitingForSecondHand ? "Song 1 · waiting for hand 2" : "Song 1"
        case .morph2: return "Interference 2 → song 2"
        case .song2: return "Song 2"
        }
    }

    // MARK: Hands

    private func handSeen(source: String) {
        if phase == .ringing {
            firstHand(source: source)
        } else if waitingForSecondHand {
            secondHand(source: source)
        }
    }

    private func firstHand(source: String) {
        guard let audio else { return }
        let id = runID
        let started = audio.beginTransition(
            onInterference: {},
            onSongClean: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.runID == id else { return }
                    self.firstSongBecameClean()
                }
            },
            onSongFinished: {}
        )
        guard started else {
            dlog("[INTERF] perform · hand while the engine is stopped · retrigger")
            onEngineLost?("interference.hand")
            return
        }
        detector.stop()
        firstHandAt = CACurrentMediaTime()
        phase = .morph1
        PerformUserLog.shared.log("Interference · hand detected after \(String(format: "%.1f", firstHandAt - ringStartedAt)) s (\(source)) → song 1")
        if hasSecondSong { scheduleSecondHandWatch(runID: id) }
    }

    private func firstSongBecameClean() {
        firstSongClean = true
        if secondHandQueued {
            secondHandQueued = false
            startSecondMorph()
            return
        }
        phase = .song1
    }

    /// The camera comes back after the cooldown; a hand still held from spectator 1 must leave first.
    private func scheduleSecondHandWatch(runID id: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + InterferenceSettings.secondHandCooldown) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.runID == id, self.isActive, !self.secondHandSeen else { return }
                self.secondHandWatchDue = true
                self.waitingForSecondHand = true
                self.startCamera(requireClearFirst: true)
                PerformUserLog.shared.log("Interference · watching for hand 2")
            }
        }
    }

    private func secondHand(source: String) {
        guard waitingForSecondHand, !secondHandSeen else { return }
        detector.stop()
        waitingForSecondHand = false
        secondHandSeen = true
        let now = CACurrentMediaTime()
        PerformUserLog.shared.log("Interference · hand 2 \(String(format: "%.1f", now - firstHandAt)) s after hand 1 (\(source)) → song 2")
        if firstSongClean {
            startSecondMorph()
        } else {
            secondHandQueued = true
            dlog("[INTERF] perform · hand 2 queued until song 1 is clean")
        }
    }

    private func startSecondMorph() {
        guard let audio else { return }
        let id = runID
        let started = audio.beginSecondTransition(
            onInterference: {},
            onSongClean: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.runID == id else { return }
                    self.phase = .song2
                }
            },
            onSongFinished: {}
        )
        if started {
            phase = .morph2
        } else {
            phase = .song1
            secondHandSeen = false
            dlog("[INTERF] perform · second transition could not start · retrigger")
            onEngineLost?("interference.hand2")
        }
    }

    // MARK: Camera / engine events

    private func startCamera(requireClearFirst: Bool) {
        do {
            try detector.start(requireClearFirst: requireClearFirst)
        } catch {
            PerformUserLog.shared.log("Interference · front camera could not start · Back Tap (Sonar canción) stands in for the hand")
            dlog("[INTERF] perform · camera start failed: \(error.localizedDescription)")
        }
    }

    private func cameraInterrupted(_ reason: String) {
        guard awaitingHand else { return }
        PerformUserLog.shared.log("Interference · camera paused (\(reason)) · use Banner call style, or Back Tap for the hand")
        dlog("[INTERF] perform · camera interrupted · \(reason) · phase=\(phase.rawValue)")
    }

    private func engineConfigurationChanged() {
        guard isActive else { return }
        dlog("[INTERF] perform · engine configuration change · phase=\(phase.rawValue)")
        onEngineLost?("interference.configurationChange")
    }
}
