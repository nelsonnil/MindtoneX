import AudioToolbox
import AVFoundation
import QuartzCore

/// Audio graph for the interference effect: ringtone loop → (hand at T) → radio static takes over →
/// band-limited song → clean song at ~T+4 s. Timeline measured from `auido.mp4`
/// (see Context `internal/interferencia-ringtone-tecnico.md` §1).
///
/// Uses its own `AVAudioEngine` and never touches `RingtoneAudioEngine`, so live-call playback
/// (banner and full screen) is unchanged. Only the Settings test lab drives this class today.
///
/// Perform integration hook points (later phase, not wired yet):
/// - `AppModel.trigger(source:)`: when `InterferenceSettings.enabled`, call `startRingtone()` instead of
///   `audio.makeAudible(...)` and start `HandGestureDetector`; the song must stay silent until the hand.
/// - `AppModel.select(_:)`: after `audio.load`, pass the same preview data to `prepare(...)`.
/// - `AppModel.handleInterruption` / `refreshArmedState`: `AVAudioEngine` stops on `interruption.began`
///   (unlike `AVAudioPlayer`); reconfigure the session, `engine.start()` and reschedule from `now − T`,
///   retrying like `schedulePlayRetries`.
/// - `AppModel.enterPerformedState` / `silence`: `stop()` plus `HandGestureDetector.stop()`.
final class InterferenceAudioEngine {
    enum EngineError: LocalizedError {
        case unreadableAsset(String)

        var errorDescription: String? {
            switch self {
            case .unreadableAsset(let name): return "Could not read \(name)."
            }
        }
    }

    enum Timeline {
        static let staticAttack: TimeInterval = 0.25
        static let ringtoneFadeEnd: TimeInterval = 1.2
        static let ringtoneStop: TimeInterval = 1.5
        static let songIn: TimeInterval = 1.2
        static let songInRamp: TimeInterval = 0.5
        static let staticReleaseStart: TimeInterval = 2.8
        static let staticReleaseEnd: TimeInterval = 3.9
        static let filterOpenStart: TimeInterval = 3.55
        static let filterOpenEnd: TimeInterval = 3.95
        static let radioHighPassHz: Float = 300
        static let radioLowPassHz: Float = 3400
    }

    /// Interference sits ~3 dB in front of ringtone and song; the master peak limiter keeps the sum clean.
    enum Level {
        static let ringtone: Float = 0.72
        static let interference: Float = 1.0
        static let song: Float = 0.85
        static let ringtoneDuckDB: Float = -15
    }

    var onConfigurationChange: (() -> Void)?

    private let engine = AVAudioEngine()
    private let ringtonePlayer = AVAudioPlayerNode()
    private let staticPlayer = AVAudioPlayerNode()
    private let songPlayer = AVAudioPlayerNode()
    private let songEQ = AVAudioUnitEQ(numberOfBands: 2)
    private let limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: kAudioUnitSubType_PeakLimiter,
        componentManufacturer: kAudioUnitManufacturer_Apple,
        componentFlags: 0,
        componentFlagsMask: 0
    ))

    private var ringtoneBuffer: AVAudioPCMBuffer?
    private var staticBuffer: AVAudioPCMBuffer?
    private var songFile: AVAudioFile?
    private var transitionTimer: Timer?
    private var transitionStart: CFTimeInterval = 0
    private var songStarted = false
    private var reachedCleanSong = false
    private var generation = 0
    private var configObserver: NSObjectProtocol?

    private var onInterference: (() -> Void)?
    private var onSongClean: (() -> Void)?
    private var onSongFinished: (() -> Void)?

    init() {
        engine.attach(ringtonePlayer)
        engine.attach(staticPlayer)
        engine.attach(songPlayer)
        engine.attach(songEQ)
        engine.attach(limiter)

        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            dlog("[INTERF] engine configuration change")
            self?.onConfigurationChange?()
        }
    }

    deinit {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
    }

    // MARK: Loading

    /// Call after the audio session is configured so the master chain matches the hardware rate.
    func prepare(ringtoneURL: URL, interferenceURL: URL, songData: Data, songFileTypeHint: String) throws {
        stop()
        let ring = try Self.loadBuffer(ringtoneURL)
        let noise = try Self.loadBuffer(interferenceURL)
        let file = try AVAudioFile(forReading: try Self.writeSongToCache(songData, fileTypeHint: songFileTypeHint))

        let mixer = engine.mainMixerNode
        for node in [ringtonePlayer, staticPlayer, songPlayer, songEQ, mixer, limiter] as [AVAudioNode] {
            engine.disconnectNodeOutput(node)
        }
        let hardwareRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        guard let masterFormat = AVAudioFormat(standardFormatWithSampleRate: hardwareRate > 0 ? hardwareRate : 48_000, channels: 2) else {
            throw EngineError.unreadableAsset("output format")
        }
        engine.connect(mixer, to: limiter, format: masterFormat)
        engine.connect(limiter, to: engine.outputNode, format: masterFormat)
        engine.connect(ringtonePlayer, to: mixer, fromBus: 0, toBus: 0, format: ring.format)
        engine.connect(staticPlayer, to: mixer, fromBus: 0, toBus: 1, format: noise.format)
        engine.connect(songPlayer, to: songEQ, format: file.processingFormat)
        engine.connect(songEQ, to: mixer, fromBus: 0, toBus: 2, format: file.processingFormat)

        ringtoneBuffer = ring
        staticBuffer = noise
        songFile = file
        engine.prepare()
        dlog("[INTERF] prepared · ringtone \(Self.seconds(ring)) s · interference \(Self.seconds(noise)) s · song \(String(format: "%.1f", Double(file.length) / file.processingFormat.sampleRate)) s")
    }

    // MARK: Playback

    /// Loops the ringtone with the static and song armed silently, until `beginTransition`.
    func startRingtone() throws {
        guard let ring = ringtoneBuffer, let noise = staticBuffer, let file = songFile else { return }
        generation += 1
        let token = generation
        configureRadioFilter()
        songStarted = false
        reachedCleanSong = false
        ringtonePlayer.stop()
        staticPlayer.stop()
        songPlayer.stop()

        if !engine.isRunning { try engine.start() }

        ringtonePlayer.volume = Level.ringtone
        ringtonePlayer.scheduleBuffer(ring, at: nil, options: .loops, completionHandler: nil)
        ringtonePlayer.play()

        staticPlayer.volume = 0
        staticPlayer.scheduleBuffer(noise, at: nil, options: .loops, completionHandler: nil)

        songPlayer.volume = 0
        let sampleRate = file.processingFormat.sampleRate
        let offsetFrames = AVAudioFramePosition(max(0, Prefs.startOffset) * sampleRate)
        let startFrame = offsetFrames < file.length - AVAudioFramePosition(sampleRate * 5) ? offsetFrames : 0
        songPlayer.scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: AVAudioFrameCount(file.length - startFrame),
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.generation == token, self.songStarted else { return }
                dlog("[INTERF] song preview finished")
                self.onSongFinished?()
            }
        }
        dlog("[INTERF] ringtone looping · route=\(RingtoneAudioEngine.routeDescription())")
    }

    /// Starts the fixed-length morph at "now" (the moment the hand was confirmed).
    /// Returns false if iOS stopped the engine (players must never `play()` on a stopped engine).
    @discardableResult
    func beginTransition(
        onInterference: @escaping () -> Void,
        onSongClean: @escaping () -> Void,
        onSongFinished: @escaping () -> Void
    ) -> Bool {
        guard engine.isRunning else {
            dlog("[INTERF] transition skipped · engine not running")
            return false
        }
        self.onInterference = onInterference
        self.onSongClean = onSongClean
        self.onSongFinished = onSongFinished
        transitionStart = CACurrentMediaTime()
        staticPlayer.volume = 0
        staticPlayer.play()
        transitionTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        transitionTimer = timer
        dlog("[INTERF] transition started")
        return true
    }

    func stop() {
        generation += 1
        transitionTimer?.invalidate()
        transitionTimer = nil
        onInterference = nil
        onSongClean = nil
        onSongFinished = nil
        songStarted = false
        ringtonePlayer.stop()
        staticPlayer.stop()
        songPlayer.stop()
        if engine.isRunning { engine.stop() }
    }

    // MARK: Transition

    private func tick() {
        guard engine.isRunning else { return }
        let t = CACurrentMediaTime() - transitionStart

        staticPlayer.volume = Level.interference * Self.staticEnvelope(t)

        if t < Timeline.ringtoneFadeEnd {
            let duckDB = Level.ringtoneDuckDB * Float(t / Timeline.ringtoneFadeEnd)
            ringtonePlayer.volume = Level.ringtone * powf(10, duckDB / 20)
        } else if t < Timeline.ringtoneStop {
            let ducked = Level.ringtone * powf(10, Level.ringtoneDuckDB / 20)
            ringtonePlayer.volume = ducked * Float(1 - (t - Timeline.ringtoneFadeEnd) / (Timeline.ringtoneStop - Timeline.ringtoneFadeEnd))
        } else if ringtonePlayer.isPlaying {
            ringtonePlayer.stop()
        }

        if t >= Timeline.staticAttack, let interferenceStarted = onInterference {
            onInterference = nil
            interferenceStarted()
        }

        if t >= Timeline.songIn {
            if !songStarted {
                songStarted = true
                songPlayer.play()
            }
            songPlayer.volume = Level.song * Float(min(1, (t - Timeline.songIn) / Timeline.songInRamp))
        }

        if t >= Timeline.filterOpenStart, t < Timeline.filterOpenEnd {
            let p = Float((t - Timeline.filterOpenStart) / (Timeline.filterOpenEnd - Timeline.filterOpenStart))
            songEQ.bands[0].frequency = Timeline.radioHighPassHz * powf(20 / Timeline.radioHighPassHz, p)
            songEQ.bands[1].frequency = Timeline.radioLowPassHz * powf(20_000 / Timeline.radioLowPassHz, p)
        }

        if t >= Timeline.filterOpenEnd, !reachedCleanSong {
            reachedCleanSong = true
            songEQ.bypass = true
            staticPlayer.stop()
            transitionTimer?.invalidate()
            transitionTimer = nil
            songPlayer.volume = Level.song
            dlog("[INTERF] clean song")
            onSongClean?()
        }
    }

    private static func staticEnvelope(_ t: TimeInterval) -> Float {
        if t < Timeline.staticAttack { return Float(t / Timeline.staticAttack) }
        if t < Timeline.staticReleaseStart { return 1 }
        if t < Timeline.staticReleaseEnd {
            return Float(1 - (t - Timeline.staticReleaseStart) / (Timeline.staticReleaseEnd - Timeline.staticReleaseStart))
        }
        return 0
    }

    private func configureRadioFilter() {
        songEQ.bypass = false
        songEQ.globalGain = 0
        let highPass = songEQ.bands[0]
        highPass.filterType = .highPass
        highPass.frequency = Timeline.radioHighPassHz
        highPass.bypass = false
        let lowPass = songEQ.bands[1]
        lowPass.filterType = .lowPass
        lowPass.frequency = Timeline.radioLowPassHz
        lowPass.bypass = false
    }

    // MARK: Helpers

    private static func loadBuffer(_ url: URL) throws -> AVAudioPCMBuffer {
        let file = try AVAudioFile(forReading: url)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw EngineError.unreadableAsset(url.lastPathComponent)
        }
        try file.read(into: buffer)
        return buffer
    }

    private static func writeSongToCache(_ data: Data, fileTypeHint: String) throws -> URL {
        let ext: String
        switch fileTypeHint {
        case AVFileType.mp3.rawValue: ext = "mp3"
        case AVFileType.wav.rawValue: ext = "wav"
        case AVFileType.caf.rawValue: ext = "caf"
        case AVFileType.aiff.rawValue: ext = "aiff"
        default: ext = "m4a"
        }
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = dir.appendingPathComponent("interference-test-song.\(ext)")
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func seconds(_ buffer: AVAudioPCMBuffer) -> String {
        String(format: "%.2f", Double(buffer.frameLength) / buffer.format.sampleRate)
    }
}
