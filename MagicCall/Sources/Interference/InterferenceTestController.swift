import AVFoundation
import QuartzCore

/// Settings test lab state machine: Play → ringtone loop + front camera → open hand → interference → song.
/// Spectators = 2: after a cooldown the camera watches for a second hand → interference audio 2 → song 2.
/// Lives only while the test sheet is open; it never arms Perform or touches the call pipeline.
@MainActor
final class InterferenceTestController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case starting
        case playingRingtone
        case handDetected
        case interference
        case playingSong
        case secondHandDetected
        case secondInterference
        case playingSecondSong
        case error(String)

        var isBusy: Bool {
            switch self {
            case .idle, .error: return false
            default: return true
            }
        }

        /// One spectator: 0 = not started; 1…4 = ringtone, hand, interference, song.
        var step: Int {
            switch self {
            case .idle, .starting, .error: return 0
            case .playingRingtone: return 1
            case .handDetected: return 2
            case .interference: return 3
            case .playingSong, .secondHandDetected, .secondInterference, .playingSecondSong: return 4
            }
        }

        /// Two spectators: 0 = not started; 1…5 = ringtone, hand 1, song 1, hand 2, song 2.
        var twoSpectatorStep: Int {
            switch self {
            case .idle, .starting, .error: return 0
            case .playingRingtone: return 1
            case .handDetected, .interference: return 2
            case .playingSong: return 3
            case .secondHandDetected, .secondInterference: return 4
            case .playingSecondSong: return 5
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var fingersSeen = 0
    @Published private(set) var handDetectedAfter: TimeInterval?
    @Published private(set) var secondHandDetectedAfter: TimeInterval?
    @Published private(set) var note: String?
    /// Front camera is looking for a hand (drives the live preview tile).
    @Published private(set) var cameraLive = false
    /// Spectators = 2: the camera is back on, waiting for the second hand.
    @Published private(set) var waitingForSecondHand = false
    /// Spectators = 2: songs picked in the test sheet (1 spectator uses `model.selected`).
    @Published private(set) var song1: PreviewTrack?
    @Published private(set) var song2: PreviewTrack?
    @Published var pickSlot = 1

    let detector = HandGestureDetector()
    private let audio = InterferenceAudioEngine()
    private var ringStartedAt: CFTimeInterval = 0
    private var firstHandAt: CFTimeInterval = 0
    private var runID = 0
    private var twoSpectatorRun = false
    private var firstSongClean = false
    private var secondHandQueued = false
    private var secondHandSeen = false
    private var interruptionObserver: NSObjectProtocol?

    init() {
        detector.onFingers = { [weak self] fingers in
            MainActor.assumeIsolated { self?.fingersSeen = fingers }
        }
        detector.onOpenHand = { [weak self] fingers in
            MainActor.assumeIsolated { self?.openHandSeen(fingers: fingers) }
        }
        detector.onInterrupted = { [weak self] reason in
            MainActor.assumeIsolated {
                guard let self, self.phase == .playingRingtone || self.waitingForSecondHand else { return }
                self.fail("\(reason). Keep this screen open and tap Play again.")
            }
        }
        audio.onConfigurationChange = { [weak self] in
            MainActor.assumeIsolated { self?.handleEngineConfigurationChange() }
        }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard raw == AVAudioSession.InterruptionType.began.rawValue else { return }
            MainActor.assumeIsolated {
                guard let self, self.phase.isBusy, self.phase != .starting else { return }
                self.fail("iOS interrupted the audio (call, alarm or Siri). Tap Play to try again.")
            }
        }
    }

    deinit {
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
    }

    // MARK: Songs (Spectators = 2)

    /// Starts from the song loaded on Home and the last song 2 an input found.
    func prefillSongs(model: AppModel) {
        if song1 == nil, model.loadState == .ready, let track = model.selected {
            song1 = track
        }
        if song2 == nil, let track = SecondSpectatorSong.shared.track {
            song2 = track
        }
        pickSlot = song1 != nil && song2 == nil ? 2 : 1
    }

    func assign(_ track: PreviewTrack, toSlot slot: Int, model: AppModel) {
        if slot == 2 {
            song2 = track
        } else {
            song1 = track
            if song2 == nil { pickSlot = 2 }
        }
        dlog("[INTERF] test song \(slot) → \(track.title) — \(track.artist)")
        Task { _ = try? await model.previews.audioData(for: track) }
    }

    func play(model: AppModel, ringtone: InterferenceSettings.Ringtone) async {
        guard !phase.isBusy else { return }
        runID += 1
        let id = runID
        note = nil
        handDetectedAfter = nil
        secondHandDetectedAfter = nil
        fingersSeen = 0
        let twoSpectators = SpectatorSettings.isTwo
        twoSpectatorRun = twoSpectators
        firstSongClean = false
        secondHandQueued = false
        secondHandSeen = false
        waitingForSecondHand = false

        let first: PreviewTrack
        var second: PreviewTrack?
        if twoSpectators {
            guard let pick1 = song1, let pick2 = song2 else {
                fail("Pick Song 1 and Song 2 first.")
                return
            }
            first = pick1
            second = pick2
        } else {
            guard let track = model.selected, model.loadState == .ready else {
                fail("No song yet. Search above and tap a match first.")
                return
            }
            first = track
        }
        guard let ringtoneURL = InterferenceSettings.bundledAudioURL(named: ringtone.resourceName) else {
            fail("\(ringtone.title) sound is missing from this build.")
            return
        }
        guard let interferenceURL = InterferenceSettings.bundledAudioURL(named: InterferenceSettings.interferenceResourceName) else {
            fail("Interference sound is missing from this build.")
            return
        }
        var secondInterferenceURL = interferenceURL
        if twoSpectators {
            if let url = InterferenceSettings.secondHandInterferenceURL {
                secondInterferenceURL = url
            } else {
                dlog("[INTERF] \(InterferenceSettings.secondHandResourceName).m4a missing · second hand reuses interference")
            }
        }

        phase = .starting
        model.pauseVoiceAndAudioForSetupUI(reason: "interference test")

        guard await CardSettings.requestCameraIfNeeded() else {
            fail("Camera access denied. Allow it in iPhone Settings → MindtoneX → Camera.")
            return
        }
        guard id == runID else { return }

        let songData: Data
        var secondStage: InterferenceAudioEngine.SecondStage?
        do {
            songData = try await model.previews.audioData(for: first)
            if let second {
                let data = try await model.previews.audioData(for: second)
                secondStage = InterferenceAudioEngine.SecondStage(
                    interferenceURL: secondInterferenceURL,
                    songData: data,
                    songFileTypeHint: second.fileTypeHint
                )
            }
        } catch {
            fail("Could not load the song preview: \(error.localizedDescription)")
            return
        }
        guard id == runID else { return }

        do {
            try model.audio.configureSession(preferIPhoneSpeaker: true)
            model.applyPerformancePlaybackVolume(reason: "interference test")
            try audio.prepare(
                ringtoneURL: ringtoneURL,
                interferenceURL: interferenceURL,
                songData: songData,
                songFileTypeHint: first.fileTypeHint,
                second: secondStage
            )
            try audio.startRingtone()
        } catch {
            fail("Audio could not start: \(RingtoneAudioEngine.describe(error))")
            return
        }

        do {
            try detector.start()
        } catch {
            fail("Front camera could not start: \(error.localizedDescription)")
            return
        }

        cameraLive = true
        ringStartedAt = CACurrentMediaTime()
        phase = .playingRingtone
        if let second {
            dlog("[INTERF] test playing · 2 spectators · \(ringtone.title) · interference → \(InterferenceSettings.secondHandTitle) · song 1=\(first.title) · song 2=\(second.title)")
        } else {
            dlog("[INTERF] test playing · \(ringtone.title) · song=\(first.title) — \(first.artist)")
        }
    }

    /// Stop button / leaving the sheet: back to Idle.
    func stop(note: String? = nil) {
        runID += 1
        detector.stop()
        audio.stop()
        fingersSeen = 0
        cameraLive = false
        waitingForSecondHand = false
        self.note = note
        if phase != .idle { dlog("[INTERF] test stopped\(note.map { " · \($0)" } ?? "")") }
        phase = .idle
    }

    private func fail(_ message: String) {
        runID += 1
        detector.stop()
        audio.stop()
        fingersSeen = 0
        cameraLive = false
        waitingForSecondHand = false
        phase = .error(message)
        dlog("[INTERF] test error · \(message)")
    }

    // MARK: Hands

    private func openHandSeen(fingers: Int) {
        if phase == .playingRingtone {
            firstHand()
        } else if waitingForSecondHand {
            secondHand()
        }
    }

    private func firstHand() {
        detector.stop()
        cameraLive = false
        firstHandAt = CACurrentMediaTime()
        handDetectedAfter = firstHandAt - ringStartedAt
        phase = .handDetected
        let id = runID
        let started = audio.beginTransition(
            onInterference: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.runID == id, self.phase == .handDetected else { return }
                    self.phase = .interference
                }
            },
            onSongClean: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.runID == id else { return }
                    self.firstSongBecameClean()
                }
            },
            onSongFinished: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.runID == id else { return }
                    self.firstSongFinished()
                }
            }
        )
        guard started else {
            fail("iOS stopped the audio just as the hand was detected. Tap Play again.")
            return
        }
        if twoSpectatorRun { scheduleSecondHandWatch(runID: id) }
    }

    private func firstSongBecameClean() {
        firstSongClean = true
        if secondHandQueued {
            secondHandQueued = false
            startSecondMorph()
            return
        }
        phase = .playingSong
    }

    private func firstSongFinished() {
        guard twoSpectatorRun else {
            stop(note: "Song preview finished. Tap Play to run it again.")
            return
        }
        guard !secondHandSeen else { return }
        note = "Song 1 preview ended — still waiting for the second hand."
        dlog("[INTERF] song 1 finished · still waiting for hand 2")
    }

    /// The camera comes back after the cooldown; a hand still held from spectator 1 must leave first.
    private func scheduleSecondHandWatch(runID id: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + InterferenceSettings.secondHandCooldown) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.runID == id, self.phase.isBusy, !self.secondHandSeen else { return }
                self.armSecondHand()
            }
        }
    }

    private func armSecondHand() {
        do {
            try detector.start(requireClearFirst: true)
        } catch {
            fail("Front camera could not restart for the second hand: \(error.localizedDescription)")
            return
        }
        fingersSeen = 0
        cameraLive = true
        waitingForSecondHand = true
        dlog("[INTERF] watching for hand 2 · \(String(format: "%.1f", CACurrentMediaTime() - firstHandAt)) s after hand 1")
    }

    private func secondHand() {
        guard twoSpectatorRun, waitingForSecondHand, !secondHandSeen else { return }
        detector.stop()
        cameraLive = false
        waitingForSecondHand = false
        secondHandSeen = true
        let now = CACurrentMediaTime()
        secondHandDetectedAfter = now - ringStartedAt
        phase = .secondHandDetected
        dlog("[INTERF] hand 2 · \(String(format: "%.1f", now - firstHandAt)) s after hand 1")
        if firstSongClean {
            startSecondMorph()
        } else {
            secondHandQueued = true
            dlog("[INTERF] hand 2 queued until song 1 is clean")
        }
    }

    private func startSecondMorph() {
        phase = .secondHandDetected
        let id = runID
        let started = audio.beginSecondTransition(
            onInterference: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.runID == id else { return }
                    self.phase = .secondInterference
                }
            },
            onSongClean: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.runID == id else { return }
                    self.phase = .playingSecondSong
                }
            },
            onSongFinished: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.runID == id else { return }
                    self.stop(note: "Song 2 preview finished. Tap Play to run it again.")
                }
            }
        )
        if !started {
            fail("iOS stopped the audio just as the second hand was detected. Tap Play again.")
        }
    }

    /// iOS rebuilt the audio route. While still waiting for the first hand, restart the ringtone; later, report it.
    private func handleEngineConfigurationChange() {
        switch phase {
        case .playingRingtone:
            do {
                try audio.startRingtone()
            } catch {
                fail("Audio route changed and the ringtone could not restart. Tap Play again.")
            }
        case .handDetected, .interference, .playingSong, .secondHandDetected, .secondInterference, .playingSecondSong:
            fail("Audio route changed during the transition. Tap Play again.")
        default:
            break
        }
    }
}
