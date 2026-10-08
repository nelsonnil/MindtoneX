import AVFoundation
import QuartzCore

/// Settings test lab state machine: Play → ringtone loop + front camera → open hand → interference → song.
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
        case error(String)

        var isBusy: Bool {
            switch self {
            case .idle, .error: return false
            default: return true
            }
        }

        /// 0 = not started; 1…4 = ringtone, hand, interference, song.
        var step: Int {
            switch self {
            case .idle, .starting, .error: return 0
            case .playingRingtone: return 1
            case .handDetected: return 2
            case .interference: return 3
            case .playingSong: return 4
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var fingersSeen = 0
    @Published private(set) var handDetectedAfter: TimeInterval?
    @Published private(set) var note: String?

    let detector = HandGestureDetector()
    private let audio = InterferenceAudioEngine()
    private var ringStartedAt: CFTimeInterval = 0
    private var runID = 0
    private var interruptionObserver: NSObjectProtocol?

    init() {
        detector.onFingers = { [weak self] fingers in
            MainActor.assumeIsolated { self?.fingersSeen = fingers }
        }
        detector.onOpenHand = { [weak self] fingers in
            MainActor.assumeIsolated { self?.handDetected(fingers: fingers) }
        }
        detector.onInterrupted = { [weak self] reason in
            MainActor.assumeIsolated {
                guard let self, self.phase == .playingRingtone else { return }
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

    func play(model: AppModel, ringtone: InterferenceSettings.Ringtone) async {
        guard !phase.isBusy else { return }
        runID += 1
        let id = runID
        note = nil
        handDetectedAfter = nil
        fingersSeen = 0

        guard let track = model.selected, model.loadState == .ready else {
            fail("No song yet. Search above and tap a match first.")
            return
        }
        guard let ringtoneURL = InterferenceSettings.bundledAudioURL(named: ringtone.resourceName) else {
            fail("\(ringtone.title) sound is missing from this build.")
            return
        }
        guard let interferenceURL = InterferenceSettings.bundledAudioURL(named: InterferenceSettings.interferenceResourceName) else {
            fail("Interference sound is missing from this build.")
            return
        }

        phase = .starting
        model.pauseVoiceAndAudioForSetupUI(reason: "interference test")

        guard await CardSettings.requestCameraIfNeeded() else {
            fail("Camera access denied. Allow it in iPhone Settings → MindtoneX → Camera.")
            return
        }
        guard id == runID else { return }

        let songData: Data
        do {
            songData = try await model.previews.audioData(for: track)
        } catch {
            fail("Could not load the song preview: \(error.localizedDescription)")
            return
        }
        guard id == runID else { return }

        do {
            try model.audio.configureSession(preferIPhoneSpeaker: true)
            try audio.prepare(
                ringtoneURL: ringtoneURL,
                interferenceURL: interferenceURL,
                songData: songData,
                songFileTypeHint: track.fileTypeHint
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

        ringStartedAt = CACurrentMediaTime()
        phase = .playingRingtone
        dlog("[INTERF] test playing · \(ringtone.title) · song=\(track.title) — \(track.artist)")
    }

    /// Stop button / leaving the sheet: back to Idle.
    func stop(note: String? = nil) {
        runID += 1
        detector.stop()
        audio.stop()
        fingersSeen = 0
        self.note = note
        if phase != .idle { dlog("[INTERF] test stopped\(note.map { " · \($0)" } ?? "")") }
        phase = .idle
    }

    private func fail(_ message: String) {
        runID += 1
        detector.stop()
        audio.stop()
        fingersSeen = 0
        phase = .error(message)
        dlog("[INTERF] test error · \(message)")
    }

    private func handDetected(fingers: Int) {
        guard phase == .playingRingtone else { return }
        detector.stop()
        handDetectedAfter = CACurrentMediaTime() - ringStartedAt
        phase = .handDetected
        let id = runID
        let started = audio.beginTransition(
            onInterference: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.runID == id else { return }
                    self.phase = .interference
                }
            },
            onSongClean: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.runID == id else { return }
                    self.phase = .playingSong
                }
            },
            onSongFinished: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.runID == id else { return }
                    self.stop(note: "Song preview finished. Tap Play to run it again.")
                }
            }
        )
        if !started {
            fail("iOS stopped the audio just as the hand was detected. Tap Play again.")
        }
    }

    /// iOS rebuilt the audio route. While still waiting for the hand, restart the ringtone; mid-morph, report it.
    private func handleEngineConfigurationChange() {
        switch phase {
        case .playingRingtone:
            do {
                try audio.startRingtone()
            } catch {
                fail("Audio route changed and the ringtone could not restart. Tap Play again.")
            }
        case .handDetected, .interference, .playingSong:
            fail("Audio route changed during the transition. Tap Play again.")
        default:
            break
        }
    }
}
