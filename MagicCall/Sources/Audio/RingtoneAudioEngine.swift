import AVFoundation

/// Reproduce un fragmento del preview como si fuera el tono de llamada.
///
/// "Standby en caliente": la sesión se activa y el reproductor suena a volumen 0 *antes* de que
/// llegue la llamada. Activar una sesión no mezclable mientras el teléfono ya está sonando puede
/// fallar (prioridad insuficiente), así que en el momento del disparo solo se sube el volumen.
final class RingtoneAudioEngine: NSObject, AVAudioPlayerDelegate {
    private(set) var player: AVAudioPlayer?
    private(set) var isAudible = false
    private var timer: Timer?
    private var clipStart: TimeInterval = 0
    private var clipEnd: TimeInterval = RingtoneLimits.defaultClipSeconds
    private var fadingAtLoopEdge = false
    private let edgeFade: TimeInterval = 0.12
    /// Tras un stop explícito (toque en escena): no hot-standby ni bucle silencioso hasta `makeAudible`.
    private(set) var holdsSilentUntilExplicitPlay = false

    var onFinishedClip: (() -> Void)?

    var duration: TimeInterval { player?.duration ?? 0 }

    // MARK: Sesión

    func configureSession(preferIPhoneSpeaker: Bool = false) throws {
        let session = AVAudioSession.sharedInstance()
        var options: AVAudioSession.CategoryOptions = []
        if Prefs.mixWithOthers { options.insert(.mixWithOthers) }
        // .playback es imprescindible: .ambient/.soloAmbient se silencian con el modo silencio.
        if VoiceAudioSession.recordCategoryActive {
            options.insert(.defaultToSpeaker)
            try session.setCategory(.playAndRecord, mode: .default, options: options)
            try? session.setAllowHapticsAndSystemSoundsDuringRecording(true)
        } else {
            try session.setCategory(.playback, mode: .default, options: options)
        }
        try session.setPrefersNoInterruptionsFromSystemAlerts(Prefs.noInterruptions)
        try session.setActive(true)
        if preferIPhoneSpeaker {
            Self.applyBuiltInSpeakerOverride(reason: "configureSession")
        }
        dlog("Sesión activa: cat=\(session.category.rawValue) opts=\(session.categoryOptions.rawValue) prefersNoInterruptionsFromSystemAlerts=\(session.prefersNoInterruptionsFromSystemAlerts) ruta=\(Self.routeDescription()) volumenMedia=\(String(format: "%.2f", session.outputVolume)) preferSpeaker=\(preferIPhoneSpeaker)")
        if preferIPhoneSpeaker, !Self.isBuiltInSpeaker() {
            dlog("⚠️ Fake Perform: salida sigue sin ser altavoz interno (\(Self.routeDescription())) — p. ej. Meta glasses A2DP puede ganar en iOS.")
        } else if !preferIPhoneSpeaker, !Self.isBuiltInSpeaker() {
            dlog("⚠️ La salida NO es el altavoz del iPhone (\(Self.routeDescription()))")
        }
        if session.outputVolume < 0.5 {
            dlog("⚠️ Volumen multimedia bajo (\(String(format: "%.2f", session.outputVolume))) — Fake Perform intentará subirlo al armar.")
        }
    }

    func deactivateSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            dlog("Sesión desactivada")
        } catch {
            dlog("No se pudo desactivar la sesión: \(error.localizedDescription)")
        }
    }

    static func routeDescription() -> String {
        AVAudioSession.sharedInstance().currentRoute.outputs
            .map { "\($0.portType.rawValue)(\($0.portName))" }
            .joined(separator: ",")
    }

    static func isBuiltInSpeaker() -> Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .builtInSpeaker }
    }

    /// Best-effort iPhone speaker for Fake Perform (`overrideOutputAudioPort` is public; BT A2DP may ignore it).
    @discardableResult
    static func applyBuiltInSpeakerOverride(reason: String) -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.overrideOutputAudioPort(.speaker)
            let onSpeaker = isBuiltInSpeaker()
            dlog("[AUDIO] overrideOutputAudioPort(.speaker) (\(reason)) route=\(routeDescription()) builtInSpeaker=\(onSpeaker)")
            return onSpeaker
        } catch {
            dlog("[AUDIO] overrideOutputAudioPort failed (\(reason)): \(describe(error))")
            return false
        }
    }

    // MARK: Carga

    func load(data: Data, fileTypeHint: String) throws {
        stop()
        let p = try AVAudioPlayer(data: data, fileTypeHint: fileTypeHint)
        p.numberOfLoops = -1
        p.volume = 0
        p.delegate = self
        p.prepareToPlay()
        player = p
        recomputeClip()
        dlog("Audio cargado: \(String(format: "%.1f", p.duration)) s, clip \(String(format: "%.1f", clipStart))–\(String(format: "%.1f", clipEnd)) s, \(data.count / 1024) KB")
    }

    func recomputeClip() {
        applyClipBounds(maxLength: min(Prefs.clipSeconds, RingtoneLimits.exportMaxSeconds))
    }

    /// Setup-screen preview: same start as ringtone export, up to `maxSeconds` (Apple ringtone cap ~30 s; export uses `RingtoneLimits.exportMaxSeconds`).
    /// Returns how long playback should run before stopping.
    @discardableResult
    func configureSetupPreview(maxSeconds: TimeInterval = RingtoneLimits.exportMaxSeconds) -> TimeInterval {
        guard player != nil else { return min(maxSeconds, RingtoneLimits.exportMaxSeconds) }
        applyClipBounds(maxLength: min(maxSeconds, RingtoneLimits.exportMaxSeconds))
        return clipEnd - clipStart
    }

    private func applyClipBounds(maxLength: TimeInterval) {
        guard let p = player else { return }
        clipStart = min(max(0, Prefs.startOffset), max(0, p.duration - 1))
        let available = max(0, p.duration - clipStart)
        let length = min(max(2, maxLength), available)
        clipEnd = clipStart + length
    }

    // MARK: Control

    /// Reproduce en silencio para mantener la sesión viva y el decodificador caliente.
    func startStandby() {
        guard !holdsSilentUntilExplicitPlay else {
            dlog("Standby omitido: silencio explícito hasta próximo play")
            return
        }
        guard let p = player else { return }
        p.volume = 0
        p.currentTime = clipStart
        let ok = p.play()
        isAudible = false
        startTimer()
        dlog("Standby en caliente: play()=\(ok)")
    }

    @discardableResult
    func makeAudible(reconfigureSession: (() throws -> Void)? = nil, preserveClipBounds: Bool = false) -> Bool {
        guard let p = player else {
            dlog("[AUDIO] makeAudible: sin reproductor")
            return false
        }
        holdsSilentUntilExplicitPlay = false
        if let reconfigureSession {
            do { try reconfigureSession() } catch {
                dlog("[AUDIO] makeAudible: reconfigure falló \(Self.describe(error))")
            }
        }
        if !preserveClipBounds { recomputeClip() }
        fadingAtLoopEdge = false
        p.currentTime = clipStart
        var ok = true
        if !p.isPlaying {
            p.volume = 0
            ok = p.play()
            if !ok {
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                    ok = p.play()
                } catch {
                    dlog("[AUDIO] makeAudible: setActive+play falló \(Self.describe(error))")
                }
            }
        }
        if ok {
            let level = Float(Prefs.fakePlaybackVolume)
            p.setVolume(level, fadeDuration: 0.02)
        } else {
            dlog("[AUDIO] makeAudible: play()=false · \(snapshot())")
        }
        isAudible = ok
        startTimer()
        return ok
    }

    /// Tras una interrupción del sistema (p. ej. llamada entrante), volver a standby sin perder el reproductor.
    func markStandbyAfterInterruption() {
        guard let p = player else { return }
        isAudible = false
        p.volume = 0
        if Prefs.hotStandby {
            if !p.isPlaying {
                p.currentTime = clipStart
                let ok = p.play()
                dlog("[AUDIO] post-interruption standby play=\(ok)")
            }
            startTimer()
        }
    }

    /// - Parameter holdUntilExplicitPlay: Tras un toque «stop» en escena: pausa y no reinicia hot-standby hasta el próximo play.
    func silence(fade: TimeInterval = 0.25, holdUntilExplicitPlay: Bool = false) {
        guard let p = player else { return }
        isAudible = false
        fadingAtLoopEdge = false
        if holdUntilExplicitPlay { holdsSilentUntilExplicitPlay = true }
        p.setVolume(0, fadeDuration: fade)
        timer?.invalidate()
        timer = nil
        let pauseAfterFade = holdUntilExplicitPlay || !Prefs.hotStandby
        if pauseAfterFade {
            DispatchQueue.main.asyncAfter(deadline: .now() + fade + 0.05) { [weak self] in
                guard let self, !self.isAudible else { return }
                self.player?.pause()
                if !Prefs.hotStandby, !holdUntilExplicitPlay {
                    self.player?.stop()
                }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        player?.stop()
        isAudible = false
        holdsSilentUntilExplicitPlay = false
        fadingAtLoopEdge = false
    }

    func unload() {
        stop()
        player = nil
    }

    func snapshot() -> String {
        guard let p = player else { return "sin reproductor" }
        let s = AVAudioSession.sharedInstance()
        return "isPlaying=\(p.isPlaying) t=\(String(format: "%.2f", p.currentTime)) vol=\(String(format: "%.2f", p.volume)) audible=\(isAudible) otherAudio=\(s.isOtherAudioPlaying) silenceHint=\(s.secondaryAudioShouldBeSilencedHint) ruta=\(Self.routeDescription())"
    }

    // MARK: Bucle del clip

    private func startTimer() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard let p = player, p.isPlaying else { return }
        let now = p.currentTime
        if !isAudible { return }
        if now >= clipEnd - edgeFade && !fadingAtLoopEdge {
            fadingAtLoopEdge = true
            p.setVolume(0, fadeDuration: edgeFade)
            if !Prefs.loopClip {
                isAudible = false
                dlog("Fin del clip (sin bucle)")
                onFinishedClip?()
            }
        }
        if now >= clipEnd || now < clipStart - 0.5 {
            p.currentTime = clipStart
            fadingAtLoopEdge = false
            if isAudible {
                p.setVolume(Float(Prefs.fakePlaybackVolume), fadeDuration: edgeFade)
            }
        }
    }

    // MARK: AVAudioPlayerDelegate

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        dlog("✗ Error de decodificación: \(error.map(Self.describe) ?? "nil")")
    }

    static func describe(_ error: Error) -> String {
        let ns = error as NSError
        return "\(ns.domain) \(ns.code) \(Self.fourCC(ns.code)) \(ns.localizedDescription)"
    }

    /// Los errores de AVAudioSession suelen ser códigos FourCC ('!pri', '!int', ...).
    static func fourCC(_ code: Int) -> String {
        let v = UInt32(truncatingIfNeeded: code)
        let bytes = [24, 16, 8, 0].map { UInt8((v >> UInt32($0)) & 0xFF) }
        guard bytes.allSatisfy({ $0 >= 32 && $0 < 127 }) else { return "" }
        return "'" + String(decoding: bytes, as: UTF8.self) + "'"
    }
}
