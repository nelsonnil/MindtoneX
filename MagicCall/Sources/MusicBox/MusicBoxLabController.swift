import AVFoundation
import QuartzCore

/// Music box lab: pick a song → transcribe its preview → A/B the original against the music box rendering.
/// Lives only while the lab sheet is open; it never arms Perform or touches the call pipeline.
@MainActor
final class MusicBoxLabController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case analyzing
        case ready
        case error(String)

        var isBusy: Bool { self == .loading || self == .analyzing }
    }

    enum Playback: Equatable {
        case none
        case original
        case musicBox
        case ai
    }

    enum AIPhase: Equatable {
        case idle
        case generating(String)
        case ready
        case error(String)

        var isGenerating: Bool {
            if case .generating = self { return true }
            return false
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var playback: Playback = .none
    @Published private(set) var rendering = false
    @Published private(set) var track: PreviewTrack?
    @Published private(set) var analysis: MusicBoxAnalysis?
    @Published private(set) var events: [MusicBoxEvent] = []
    @Published private(set) var analysisMs: Int?
    @Published private(set) var note: String?
    @Published private(set) var aiPhase: AIPhase = .idle
    @Published private(set) var replicateConfigured = ReplicateMusicBoxSettings.isConfigured
    @Published var options = MusicBoxOptions() {
        didSet {
            guard options != oldValue else { return }
            if options.style != oldValue.style {
                cancelAI()
                aiData = nil
                aiPhase = .idle
            }
            guard analysis != nil else { return }
            if playback == .musicBox { stopPlayback() }
            Task { await render() }
        }
    }

    private var songData: Data?
    private var rendered: AVAudioPCMBuffer?
    private var renderedStyle: MusicBoxStyle = .musicBox
    private var originalPlayer: AVAudioPlayer?
    private let originalFinish = PlayerFinishRelay()
    private var aiPlayer: AVAudioPlayer?
    private let aiFinish = PlayerFinishRelay()
    private var aiData: Data?
    private let replicateClient = ReplicateMusicBoxClient()
    private var aiTask: Task<Void, Never>?
    private var aiPredictionID: String?
    private var aiGenerationID = 0
    private let boxPlayer = MusicBoxPlayer()
    private var runID = 0
    private var renderID = 0
    private var playID = 0

    var canPlayMusicBox: Bool { phase == .ready && rendered != nil && !rendering }
    var canPlayOriginal: Bool { songData != nil && !phase.isBusy }
    var canGenerateAI: Bool { track != nil && replicateConfigured && !aiPhase.isGenerating }
    var canPlayAI: Bool { aiData != nil && !aiPhase.isGenerating }
    var replicateTokenHint: String? { ReplicateMusicBoxSettings.tokenHint }

    func select(_ track: PreviewTrack, model: AppModel) {
        stopPlayback()
        cancelAI()
        aiData = nil
        aiPhase = .idle
        runID += 1
        let id = runID
        self.track = track
        analysis = nil
        events = []
        rendered = nil
        songData = nil
        analysisMs = nil
        note = nil
        phase = .loading
        Task {
            do {
                let data = try await model.previews.audioData(for: track)
                guard id == runID else { return }
                songData = data
                phase = .analyzing
                let hint = track.fileTypeHint
                let t0 = CACurrentMediaTime()
                let result = try await Task.detached(priority: .userInitiated) {
                    try MusicBoxAnalyzer.analyze(data: data, fileTypeHint: hint)
                }.value
                guard id == runID else { return }
                analysisMs = PreviewService.ms(since: t0)
                analysis = result
                guard !result.melody.isEmpty else {
                    phase = .error("No clear melody in this preview — try another song.")
                    return
                }
                await render()
                guard id == runID else { return }
                phase = .ready
                dlog("[MUSICBOX] \(track.title) — \(track.artist) · \(result.melody.count) notes · \(result.keyName) · bpm=\(result.bpm.map { String(Int($0.rounded())) } ?? "?") · \(analysisMs ?? 0) ms")
            } catch {
                guard id == runID else { return }
                phase = .error("Could not analyze the preview: \(error.localizedDescription)")
                dlog("✗ [MUSICBOX] \(track.title) · \(error.localizedDescription)")
            }
        }
    }

    private func render() async {
        guard let analysis, let track else { return }
        renderID += 1
        let id = renderID
        let options = options
        let seed = Self.seed(for: track)
        rendering = true
        let output = await Task.detached(priority: .userInitiated) { () -> ([MusicBoxEvent], AVAudioPCMBuffer?) in
            let events = MusicBoxArranger.arrange(analysis, options: options, seed: seed)
            return (events, MusicBoxSynth.render(events, style: options.style, seed: seed))
        }.value
        guard id == renderID else { return }
        events = output.0
        rendered = output.1
        renderedStyle = options.style
        rendering = false
    }

    // MARK: Replicate AI

    func saveReplicateToken(_ token: String) {
        ReplicateMusicBoxSettings.saveToken(token)
        replicateConfigured = ReplicateMusicBoxSettings.isConfigured
        if !replicateConfigured {
            aiPhase = .error("The Replicate token could not be saved.")
        } else if case .error = aiPhase {
            aiPhase = .idle
        }
    }

    func removeReplicateToken() {
        cancelAI()
        ReplicateMusicBoxSettings.saveToken(nil)
        replicateConfigured = false
        aiData = nil
        aiPhase = .idle
    }

    func generateAI(model: AppModel) {
        guard let track, canGenerateAI else { return }
        stopPlayback()
        aiData = nil
        aiGenerationID += 1
        let generationID = aiGenerationID
        let style = options.style
        let client = replicateClient
        aiPhase = .generating("Preparing the song…")
        dlog("[MUSICBOX-AI] generate \(style.title) · \(track.title) — \(track.artist)")

        aiTask = Task { [weak self] in
            guard let self else { return }
            do {
                let data: Data
                if let songData {
                    data = songData
                } else {
                    data = try await model.previews.audioData(for: track)
                    guard generationID == aiGenerationID else { return }
                    songData = data
                }
                let output = try await client.generate(
                    track: track,
                    songData: data,
                    style: style,
                    onPredictionCreated: { [weak self] predictionID in
                        Task { @MainActor [weak self] in
                            guard let self, generationID == self.aiGenerationID else { return }
                            self.aiPredictionID = predictionID
                        }
                    },
                    onStatus: { [weak self] status in
                        Task { @MainActor [weak self] in
                            guard let self, generationID == self.aiGenerationID else { return }
                            self.aiPhase = .generating(status)
                        }
                    }
                )
                guard generationID == aiGenerationID else { return }
                aiData = output
                aiPhase = .ready
                aiPredictionID = nil
                dlog("[MUSICBOX-AI] ready · \(output.count / 1024) KB · \(style.title)")
            } catch is CancellationError {
                guard generationID == aiGenerationID else { return }
                aiPhase = .idle
            } catch {
                guard generationID == aiGenerationID else { return }
                aiPhase = .error(error.localizedDescription)
                dlog("✗ [MUSICBOX-AI] \(error.localizedDescription)")
            }
        }
    }

    func cancelAI() {
        aiGenerationID += 1
        aiTask?.cancel()
        aiTask = nil
        if let aiPredictionID {
            let client = replicateClient
            Task { await client.cancel(predictionID: aiPredictionID) }
        }
        aiPredictionID = nil
        if aiPhase.isGenerating { aiPhase = .idle }
    }

    func toggleAI(model: AppModel) {
        if playback == .ai {
            stopPlayback()
            return
        }
        stopPlayback()
        guard let aiData else { return }
        do {
            try model.audio.configureSession(preferIPhoneSpeaker: true)
            let player = try AVAudioPlayer(data: aiData, fileTypeHint: AVFileType.wav.rawValue)
            playID += 1
            let id = playID
            aiFinish.onFinish = { [weak self] in
                guard let self, self.playID == id else { return }
                self.playback = .none
            }
            player.delegate = aiFinish
            player.play()
            aiPlayer = player
            playback = .ai
            note = nil
        } catch {
            note = "AI version could not play: \(RingtoneAudioEngine.describe(error))"
        }
    }

    // MARK: Playback

    func toggleOriginal(model: AppModel) {
        if playback == .original {
            stopPlayback()
            return
        }
        stopPlayback()
        guard let songData, let track else { return }
        do {
            try model.audio.configureSession(preferIPhoneSpeaker: true)
            let player = try AVAudioPlayer(data: songData, fileTypeHint: track.fileTypeHint)
            playID += 1
            let id = playID
            originalFinish.onFinish = { [weak self] in
                guard let self, self.playID == id else { return }
                self.playback = .none
            }
            player.delegate = originalFinish
            player.play()
            originalPlayer = player
            playback = .original
            note = nil
        } catch {
            note = "Original could not play: \(RingtoneAudioEngine.describe(error))"
        }
    }

    func toggleMusicBox(model: AppModel) {
        if playback == .musicBox {
            stopPlayback()
            return
        }
        stopPlayback()
        guard let rendered else { return }
        do {
            try model.audio.configureSession(preferIPhoneSpeaker: true)
            playID += 1
            let id = playID
            try boxPlayer.play(rendered, style: renderedStyle) { [weak self] in
                guard let self, self.playID == id else { return }
                self.playback = .none
            }
            playback = .musicBox
            note = nil
            dlog("[MUSICBOX] play \(renderedStyle.title) · route=\(RingtoneAudioEngine.routeDescription())")
        } catch {
            note = "Music box could not play: \(RingtoneAudioEngine.describe(error))"
        }
    }

    func stopPlayback() {
        playID += 1
        originalPlayer?.stop()
        originalPlayer = nil
        aiPlayer?.stop()
        aiPlayer = nil
        boxPlayer.stop()
        playback = .none
    }

    private static func seed(for track: PreviewTrack) -> UInt64 {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in track.id.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return hash
    }
}

private final class PlayerFinishRelay: NSObject, AVAudioPlayerDelegate {
    var onFinish: (@MainActor () -> Void)?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let onFinish = onFinish
        DispatchQueue.main.async { MainActor.assumeIsolated { onFinish?() } }
    }
}

/// Plays a rendered buffer through a per-style speaker colouring: low cut, softened air, room.
final class MusicBoxPlayer {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 2)
    private let reverb = AVAudioUnitReverb()
    private var connectedFormat: AVAudioFormat?

    init() {
        engine.attach(node)
        engine.attach(eq)
        engine.attach(reverb)
        eq.bands[0].filterType = .highPass
        eq.bands[0].bypass = false
        eq.bands[1].filterType = .highShelf
        eq.bands[1].frequency = 6000
        eq.bands[1].bypass = false
    }

    private func colour(for style: MusicBoxStyle) {
        let (lowCut, air, preset, wet): (Float, Float, AVAudioUnitReverbPreset, Float)
        switch style {
        case .musicBox: (lowCut, air, preset, wet) = (250, -4, .smallRoom, 20)
        case .marimba: (lowCut, air, preset, wet) = (120, -2, .mediumRoom, 18)
        case .nokia: (lowCut, air, preset, wet) = (450, -6, .smallRoom, 0)
        case .polyphonic: (lowCut, air, preset, wet) = (150, -3, .smallRoom, 8)
        }
        eq.bands[0].frequency = lowCut
        eq.bands[1].gain = air
        reverb.loadFactoryPreset(preset)
        reverb.wetDryMix = wet
    }

    /// `onFinish` runs on the main queue, also after `stop()`.
    func play(_ buffer: AVAudioPCMBuffer, style: MusicBoxStyle, onFinish: @escaping @MainActor () -> Void) throws {
        stop()
        colour(for: style)
        if connectedFormat != buffer.format {
            engine.connect(node, to: eq, format: buffer.format)
            engine.connect(eq, to: reverb, format: buffer.format)
            engine.connect(reverb, to: engine.mainMixerNode, format: buffer.format)
            connectedFormat = buffer.format
        }
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
        node.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { onFinish() } }
        }
        node.play()
    }

    func stop() {
        node.stop()
        if engine.isRunning { engine.stop() }
    }
}
