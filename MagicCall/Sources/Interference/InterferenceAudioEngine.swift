import AudioToolbox
import AVFoundation
import QuartzCore

/// Audio graph for the interference effect: ringtone loop → (hand at T) → radio static takes over →
/// band-limited song → clean song at ~T+4 s. Timeline measured from `auido.mp4`
/// (see Context `internal/interferencia-ringtone-tecnico.md` §1).
///
/// Spectators = 2 (experimental): an optional second stage replays the same morph on the second hand —
/// interference 2 takes over song 1 and opens into song 2.
///
/// Uses its own `AVAudioEngine` and never touches `RingtoneAudioEngine`. Driven by the Settings test lab
/// and, in Perform, by `InterferenceShowController` (real call → ringtone → hand → song). iOS stops an
/// `AVAudioEngine` on `interruption.began` and on configuration changes (unlike `AVAudioPlayer`), so
/// Perform calls `resume()` to restart it where the effect was.
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

    /// Spectators = 2: second interference loop and second song, started by `beginSecondTransition`.
    struct SecondStage {
        let interferenceURL: URL
        let songData: Data
        let songFileTypeHint: String
    }

    /// Where the effect is, so `resume()` can rebuild it after iOS stopped the engine.
    enum Stage: String {
        case idle
        case ringing
        case morph1
        case song1
        case morph2
        case song2
    }

    /// One morph: `outgoing` (ringtone, or song 1 on the second hand) → `interference` → `incoming`.
    private struct Morph {
        let outgoing: AVAudioPlayerNode
        let outgoingLevel: Float
        let interference: AVAudioPlayerNode
        let incoming: AVAudioPlayerNode
        let incomingEQ: AVAudioUnitEQ
        let isSecond: Bool
    }

    var onConfigurationChange: (() -> Void)?
    /// Perform: the clean song starts over when its preview ends instead of reporting "finished".
    var loopSongs = false

    private(set) var stage: Stage = .idle

    private let engine = AVAudioEngine()
    private let ringtonePlayer = AVAudioPlayerNode()
    private let staticPlayer = AVAudioPlayerNode()
    private let songPlayer = AVAudioPlayerNode()
    private let songEQ = AVAudioUnitEQ(numberOfBands: 2)
    private let static2Player = AVAudioPlayerNode()
    private let song2Player = AVAudioPlayerNode()
    private let song2EQ = AVAudioUnitEQ(numberOfBands: 2)
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
    private var static2Buffer: AVAudioPCMBuffer?
    private var song2File: AVAudioFile?
    private var transitionTimer: Timer?
    private var transitionStart: CFTimeInterval = 0
    private var morph: Morph?
    private var incomingStarted = false
    private var songStarted = false
    private var song2Started = false
    private var secondMorphStarted = false
    /// Host time and file frame at which each song's current segment started playing.
    private var songAnchor: (time: CFTimeInterval, frame: AVAudioFramePosition)?
    private var song2Anchor: (time: CFTimeInterval, frame: AVAudioFramePosition)?
    /// Set by a configuration change: iOS stopped or rebuilt the graph, players need rescheduling.
    private var needsResume = false
    private var generation = 0
    private var configObserver: NSObjectProtocol?

    private var onInterference: (() -> Void)?
    private var onSongClean: (() -> Void)?
    private var onSongFinished: (() -> Void)?
    private var onSecondSongFinished: (() -> Void)?

    /// True when the last `prepare` loaded interference 2 + song 2.
    var hasSecondStage: Bool { static2Buffer != nil && song2File != nil }

    var isRunning: Bool { engine.isRunning }

    init() {
        for node in [ringtonePlayer, staticPlayer, songPlayer, songEQ, static2Player, song2Player, song2EQ, limiter] as [AVAudioNode] {
            engine.attach(node)
        }

        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            dlog("[INTERF] engine configuration change")
            guard let self else { return }
            if self.stage != .idle { self.needsResume = true }
            self.onConfigurationChange?()
        }
    }

    deinit {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
    }

    // MARK: Loading

    /// Call after the audio session is configured so the master chain matches the hardware rate.
    func prepare(
        ringtoneURL: URL,
        interferenceURL: URL,
        songData: Data,
        songFileTypeHint: String,
        second: SecondStage? = nil
    ) throws {
        stop()
        let ring = try Self.loadBuffer(ringtoneURL)
        let noise = try Self.loadBuffer(interferenceURL)
        let file = try AVAudioFile(forReading: try Self.writeSongToCache(songData, fileTypeHint: songFileTypeHint, name: "interference-test-song"))
        var noise2: AVAudioPCMBuffer?
        var file2: AVAudioFile?
        if let second {
            noise2 = try Self.loadBuffer(second.interferenceURL)
            file2 = try AVAudioFile(forReading: try Self.writeSongToCache(
                second.songData,
                fileTypeHint: second.songFileTypeHint,
                name: "interference-test-song2"
            ))
        }

        let mixer = engine.mainMixerNode
        for node in [ringtonePlayer, staticPlayer, songPlayer, songEQ, static2Player, song2Player, song2EQ, mixer, limiter] as [AVAudioNode] {
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
        if let noise2, let file2 {
            engine.connect(static2Player, to: mixer, fromBus: 0, toBus: 3, format: noise2.format)
            engine.connect(song2Player, to: song2EQ, format: file2.processingFormat)
            engine.connect(song2EQ, to: mixer, fromBus: 0, toBus: 4, format: file2.processingFormat)
        }

        ringtoneBuffer = ring
        staticBuffer = noise
        songFile = file
        static2Buffer = noise2
        song2File = file2
        engine.prepare()
        var summary = "[INTERF] prepared · ringtone \(Self.seconds(ring)) s · interference \(Self.seconds(noise)) s · song \(Self.seconds(file)) s"
        if let noise2, let file2 {
            summary += " · 2nd hand: interference \(Self.seconds(noise2)) s · song 2 \(Self.seconds(file2)) s"
        }
        dlog(summary)
    }

    // MARK: Playback

    /// Loops the ringtone with the static and song(s) armed silently, until `beginTransition`.
    func startRingtone() throws {
        guard let ring = ringtoneBuffer, let noise = staticBuffer, let file = songFile else { return }
        generation += 1
        let token = generation
        transitionTimer?.invalidate()
        transitionTimer = nil
        morph = nil
        onInterference = nil
        onSongClean = nil
        incomingStarted = false
        songStarted = false
        song2Started = false
        secondMorphStarted = false
        songAnchor = nil
        song2Anchor = nil
        configureRadioFilter(songEQ)
        stopAllPlayers()

        if !engine.isRunning { try engine.start() }
        needsResume = false
        stage = .ringing

        ringtonePlayer.volume = Level.ringtone
        ringtonePlayer.scheduleBuffer(ring, at: nil, options: .loops, completionHandler: nil)
        ringtonePlayer.play()

        staticPlayer.volume = 0
        staticPlayer.scheduleBuffer(noise, at: nil, options: .loops, completionHandler: nil)

        songPlayer.volume = 0
        scheduleSong(file, on: songPlayer, token: token, isSecond: false)

        armSecondStageSilently(token: token)
        dlog("[INTERF] ringtone looping · route=\(RingtoneAudioEngine.routeDescription())\(hasSecondStage ? " · second hand armed" : "")")
    }

    /// Starts the fixed-length morph at "now" (the moment the hand was confirmed).
    /// Returns false if iOS stopped the engine (players must never `play()` on a stopped engine).
    @discardableResult
    func beginTransition(
        onInterference: @escaping () -> Void,
        onSongClean: @escaping () -> Void,
        onSongFinished: @escaping () -> Void
    ) -> Bool {
        guard engine.isRunning, stage == .ringing else {
            dlog("[INTERF] transition skipped · engine running=\(engine.isRunning) · stage=\(stage.rawValue)")
            return false
        }
        self.onSongFinished = onSongFinished
        startMorph(
            Morph(
                outgoing: ringtonePlayer,
                outgoingLevel: Level.ringtone,
                interference: staticPlayer,
                incoming: songPlayer,
                incomingEQ: songEQ,
                isSecond: false
            ),
            onInterference: onInterference,
            onSongClean: onSongClean
        )
        stage = .morph1
        dlog("[INTERF] transition started")
        return true
    }

    /// Spectators = 2, second hand: interference 2 takes over song 1 and morphs into song 2.
    /// Only after the first morph reached the clean song. Returns false when it cannot start.
    @discardableResult
    func beginSecondTransition(
        onInterference: @escaping () -> Void,
        onSongClean: @escaping () -> Void,
        onSongFinished: @escaping () -> Void
    ) -> Bool {
        guard engine.isRunning, hasSecondStage else {
            dlog("[INTERF] second transition skipped · engine running=\(engine.isRunning) · stage 2=\(hasSecondStage)")
            return false
        }
        guard morph == nil, !secondMorphStarted, stage == .song1 else {
            dlog("[INTERF] second transition skipped · stage=\(stage.rawValue)")
            return false
        }
        secondMorphStarted = true
        onSecondSongFinished = onSongFinished
        startMorph(
            Morph(
                outgoing: songPlayer,
                outgoingLevel: Level.song,
                interference: static2Player,
                incoming: song2Player,
                incomingEQ: song2EQ,
                isSecond: true
            ),
            onInterference: onInterference,
            onSongClean: onSongClean
        )
        stage = .morph2
        dlog("[INTERF] second transition started")
        return true
    }

    /// After an interruption or a configuration change: restart the engine where the effect was.
    /// Ringing restarts the ringtone loop; once a hand has been seen, the current song continues clean
    /// from about where it was (a morph cut short jumps to its clean song). No-op while still running fine.
    func resume() throws {
        guard stage != .idle else { return }
        guard !engine.isRunning || needsResume else { return }
        if !engine.isRunning { try engine.start() }
        needsResume = false
        switch stage {
        case .idle:
            return
        case .ringing:
            try startRingtone()
            dlog("[INTERF] resumed · ringtone")
        case .morph1, .song1:
            resumeClean(isSecond: false)
        case .morph2, .song2:
            resumeClean(isSecond: true)
        }
    }

    func stop() {
        generation += 1
        transitionTimer?.invalidate()
        transitionTimer = nil
        morph = nil
        onInterference = nil
        onSongClean = nil
        onSongFinished = nil
        onSecondSongFinished = nil
        incomingStarted = false
        songStarted = false
        song2Started = false
        secondMorphStarted = false
        songAnchor = nil
        song2Anchor = nil
        needsResume = false
        stage = .idle
        stopAllPlayers()
        if engine.isRunning { engine.stop() }
    }

    func snapshot() -> String {
        "stage=\(stage.rawValue) running=\(engine.isRunning) stage2=\(hasSecondStage) route=\(RingtoneAudioEngine.routeDescription())"
    }

    // MARK: Transition

    private func startMorph(_ next: Morph, onInterference: @escaping () -> Void, onSongClean: @escaping () -> Void) {
        self.onInterference = onInterference
        self.onSongClean = onSongClean
        morph = next
        incomingStarted = false
        transitionStart = CACurrentMediaTime()
        next.interference.volume = 0
        next.interference.play()
        transitionTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        transitionTimer = timer
    }

    private func tick() {
        guard engine.isRunning, let morph else { return }
        let t = CACurrentMediaTime() - transitionStart

        morph.interference.volume = Level.interference * Self.staticEnvelope(t)

        if t < Timeline.ringtoneFadeEnd {
            let duckDB = Level.ringtoneDuckDB * Float(t / Timeline.ringtoneFadeEnd)
            morph.outgoing.volume = morph.outgoingLevel * powf(10, duckDB / 20)
        } else if t < Timeline.ringtoneStop {
            let ducked = morph.outgoingLevel * powf(10, Level.ringtoneDuckDB / 20)
            morph.outgoing.volume = ducked * Float(1 - (t - Timeline.ringtoneFadeEnd) / (Timeline.ringtoneStop - Timeline.ringtoneFadeEnd))
        } else if morph.outgoing.isPlaying {
            morph.outgoing.stop()
        }

        if t >= Timeline.staticAttack, let interferenceStarted = onInterference {
            onInterference = nil
            interferenceStarted()
        }

        if t >= Timeline.songIn {
            if !incomingStarted {
                incomingStarted = true
                startIncomingSong(isSecond: morph.isSecond, player: morph.incoming)
            }
            morph.incoming.volume = Level.song * Float(min(1, (t - Timeline.songIn) / Timeline.songInRamp))
        }

        if t >= Timeline.filterOpenStart, t < Timeline.filterOpenEnd {
            let p = Float((t - Timeline.filterOpenStart) / (Timeline.filterOpenEnd - Timeline.filterOpenStart))
            morph.incomingEQ.bands[0].frequency = Timeline.radioHighPassHz * powf(20 / Timeline.radioHighPassHz, p)
            morph.incomingEQ.bands[1].frequency = Timeline.radioLowPassHz * powf(20_000 / Timeline.radioLowPassHz, p)
        }

        if t >= Timeline.filterOpenEnd {
            morph.incomingEQ.bypass = true
            morph.interference.stop()
            morph.incoming.volume = Level.song
            transitionTimer?.invalidate()
            transitionTimer = nil
            self.morph = nil
            stage = morph.isSecond ? .song2 : .song1
            dlog("[INTERF] clean song\(morph.isSecond ? " 2" : "")")
            let clean = onSongClean
            onSongClean = nil
            clean?()
        }
    }

    private func startIncomingSong(isSecond: Bool, player: AVAudioPlayerNode) {
        if isSecond {
            song2Started = true
            if let file = song2File { song2Anchor = (CACurrentMediaTime(), Self.baseStartFrame(file)) }
        } else {
            songStarted = true
            if let file = songFile { songAnchor = (CACurrentMediaTime(), Self.baseStartFrame(file)) }
        }
        player.play()
    }

    /// Rebuilds playback on a running engine: only the current song, clean, from where it was.
    private func resumeClean(isSecond: Bool) {
        generation += 1
        let token = generation
        transitionTimer?.invalidate()
        transitionTimer = nil
        let pendingClean = onSongClean
        morph = nil
        onInterference = nil
        onSongClean = nil
        let player = isSecond ? song2Player : songPlayer
        let eq = isSecond ? song2EQ : songEQ
        let anchor = isSecond ? song2Anchor : songAnchor
        stopAllPlayers()
        guard let file = isSecond ? song2File : songFile else { return }
        let frame = currentFrame(of: file, anchor: anchor)
        eq.bypass = true
        player.volume = Level.song
        scheduleSong(file, on: player, token: token, isSecond: isSecond, startFrame: frame)
        if isSecond {
            song2Started = true
            secondMorphStarted = true
            song2Anchor = (CACurrentMediaTime(), frame)
            stage = .song2
        } else {
            songStarted = true
            songAnchor = (CACurrentMediaTime(), frame)
            stage = .song1
            armSecondStageSilently(token: token)
        }
        player.play()
        let seconds = Double(frame) / file.processingFormat.sampleRate
        dlog("[INTERF] resumed · song \(isSecond ? 2 : 1) clean at \(String(format: "%.1f", seconds)) s")
        pendingClean?()
    }

    /// Interference 2 and song 2 scheduled silently so the second hand can still start them.
    private func armSecondStageSilently(token: Int) {
        guard let noise2 = static2Buffer, let file2 = song2File else { return }
        configureRadioFilter(song2EQ)
        static2Player.volume = 0
        static2Player.scheduleBuffer(noise2, at: nil, options: .loops, completionHandler: nil)
        song2Player.volume = 0
        scheduleSong(file2, on: song2Player, token: token, isSecond: true)
    }

    private func stopAllPlayers() {
        ringtonePlayer.stop()
        staticPlayer.stop()
        songPlayer.stop()
        if hasSecondStage {
            static2Player.stop()
            song2Player.stop()
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

    private func configureRadioFilter(_ eq: AVAudioUnitEQ) {
        eq.bypass = false
        eq.globalGain = 0
        let highPass = eq.bands[0]
        highPass.filterType = .highPass
        highPass.frequency = Timeline.radioHighPassHz
        highPass.bypass = false
        let lowPass = eq.bands[1]
        lowPass.filterType = .lowPass
        lowPass.frequency = Timeline.radioLowPassHz
        lowPass.bypass = false
    }

    // MARK: Songs

    /// First frame used for a preview (`Prefs.startOffset`, unless the file is too short for it).
    private static func baseStartFrame(_ file: AVAudioFile) -> AVAudioFramePosition {
        let sampleRate = file.processingFormat.sampleRate
        let offsetFrames = AVAudioFramePosition(max(0, Prefs.startOffset) * sampleRate)
        return offsetFrames < file.length - AVAudioFramePosition(sampleRate * 5) ? offsetFrames : 0
    }

    /// Where a playing song is now, from its anchor; past the end it starts over.
    private func currentFrame(of file: AVAudioFile, anchor: (time: CFTimeInterval, frame: AVAudioFramePosition)?) -> AVAudioFramePosition {
        let base = Self.baseStartFrame(file)
        guard let anchor else { return base }
        let sampleRate = file.processingFormat.sampleRate
        let frame = anchor.frame + AVAudioFramePosition(max(0, CACurrentMediaTime() - anchor.time) * sampleRate)
        return frame < file.length - AVAudioFramePosition(sampleRate * 0.5) ? frame : base
    }

    /// Schedules the preview, silent until its morph calls `play()`. Song 1 stops reporting once the
    /// second morph took over (that morph stops it). With `loopSongs` the clean song starts over at the end.
    private func scheduleSong(
        _ file: AVAudioFile,
        on player: AVAudioPlayerNode,
        token: Int,
        isSecond: Bool,
        startFrame: AVAudioFramePosition? = nil
    ) {
        let start = startFrame ?? Self.baseStartFrame(file)
        guard start < file.length else { return }
        player.scheduleSegment(
            file,
            startingFrame: start,
            frameCount: AVAudioFrameCount(file.length - start),
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                if isSecond {
                    guard self.song2Started else { return }
                } else {
                    guard self.songStarted, !self.secondMorphStarted else { return }
                }
                if self.loopSongs {
                    self.loopSong(isSecond: isSecond, token: token)
                    return
                }
                dlog("[INTERF] song\(isSecond ? " 2" : "") preview finished")
                if isSecond {
                    self.onSecondSongFinished?()
                } else {
                    self.onSongFinished?()
                }
            }
        }
    }

    private func loopSong(isSecond: Bool, token: Int) {
        guard engine.isRunning, let file = isSecond ? song2File : songFile else { return }
        let player = isSecond ? song2Player : songPlayer
        let start = Self.baseStartFrame(file)
        scheduleSong(file, on: player, token: token, isSecond: isSecond, startFrame: start)
        if isSecond {
            song2Anchor = (CACurrentMediaTime(), start)
        } else {
            songAnchor = (CACurrentMediaTime(), start)
        }
        if !player.isPlaying { player.play() }
        dlog("[INTERF] song\(isSecond ? " 2" : "") starts over")
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

    private static func writeSongToCache(_ data: Data, fileTypeHint: String, name: String) throws -> URL {
        let ext: String
        switch fileTypeHint {
        case AVFileType.mp3.rawValue: ext = "mp3"
        case AVFileType.wav.rawValue: ext = "wav"
        case AVFileType.caf.rawValue: ext = "caf"
        case AVFileType.aiff.rawValue: ext = "aiff"
        default: ext = "m4a"
        }
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = dir.appendingPathComponent("\(name).\(ext)")
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func seconds(_ buffer: AVAudioPCMBuffer) -> String {
        String(format: "%.2f", Double(buffer.frameLength) / buffer.format.sampleRate)
    }

    private static func seconds(_ file: AVAudioFile) -> String {
        String(format: "%.1f", Double(file.length) / file.processingFormat.sampleRate)
    }
}
