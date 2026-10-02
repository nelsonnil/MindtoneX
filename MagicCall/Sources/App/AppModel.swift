import AVFoundation
import QuartzCore
import SwiftUI
import UIKit

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    enum Phase { case setup, stage }

    enum LoadState: Equatable {
        case idle
        case searching
        case downloading
        case ready
        case failed(String)
    }

    @Published var phase: Phase = .setup
    @Published var query = ""
    @Published private(set) var results: [PreviewTrack] = []
    @Published private(set) var selected: PreviewTrack?
    @Published private(set) var loadState: LoadState = .idle
    @Published private(set) var isArmed = false
    @Published private(set) var isAudible = false
    @Published private(set) var timings = ""
    @Published var showDebugOverlay = false
    @Published private(set) var probeResults: [PrivateProbes.Result] = []

    let previews = PreviewService()
    let audio = RingtoneAudioEngine()
    let calls = CallMonitor()

    private var observers: [NSObjectProtocol] = []
    private var volumeObservation: NSKeyValueObservation?
    private var ignoreVolumeChangesUntil: CFTimeInterval = 0
    private var incomingCallID: UUID?
    private var incomingDetectedAt: CFTimeInterval = 0
    private var currentAudio: (data: Data, hint: String)?
    @Published private(set) var exportedRingtone: URL?
    @Published var showingDiscreetRingtonePrep = false
    @Published private(set) var ringtoneStaged = false

    private init() {
        Prefs.registerDefaults()
        DebugLog.shared.logDeviceHeader()
        calls.onEvent = { [weak self] event, call in
            MainActor.assumeIsolated { self?.handle(event, uuid: call.uuid) }
        }
        calls.start()
        audio.onFinishedClip = { [weak self] in
            MainActor.assumeIsolated { self?.isAudible = false }
        }
        installObservers()
        Task { await previews.warmUp() }
        #if MAGIC_PRIVATE_PROBES
        if Prefs.darwinSignals { _ = PrivateProbes.darwinSignalsStart() }
        #endif
    }

    // MARK: Canción

    func search() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        loadState = .searching
        let t0 = CACurrentMediaTime()
        do {
            let found = try await previews.search(q)
            results = found
            let searchMs = PreviewService.ms(since: t0)
            dlog("Búsqueda “\(q)” → \(found.count) candidatos en \(searchMs) ms. Mejor: \(found[0].title) — \(found[0].artist) [\(found[0].source.rawValue)]")
            await select(found[0], searchMs: searchMs)
        } catch {
            results = []
            loadState = .failed(error.localizedDescription)
            dlog("✗ Búsqueda “\(q)”: \(error.localizedDescription)")
        }
    }

    func select(_ track: PreviewTrack, searchMs: Int? = nil) async {
        selected = track
        loadState = .downloading
        let t0 = CACurrentMediaTime()
        do {
            let data = try await previews.audioData(for: track)
            try audio.load(data: data, fileTypeHint: track.fileTypeHint)
            currentAudio = (data, track.fileTypeHint)
            exportedRingtone = nil
            ringtoneStaged = false
            let downloadMs = PreviewService.ms(since: t0)
            timings = [searchMs.map { "búsqueda \($0) ms" }, "audio listo \(downloadMs) ms"].compactMap { $0 }.joined(separator: " · ")
            loadState = .ready
            dlog("Listo: \(track.title) — \(track.artist). \(timings)")
            if Prefs.autoStageRingtone {
                Task { await stageRingtoneFile(showShare: false, discreet: false) }
            }
            if isArmed {
                try? audio.configureSession()
                if Prefs.hotStandby { audio.startStandby() }
            }
        } catch {
            loadState = .failed(error.localizedDescription)
            dlog("✗ Cargar audio: \(error.localizedDescription)")
        }
    }

    /// Escucha 3 s del fragmento desde la pantalla de preparación (no en escena).
    func audition() {
        guard loadState == .ready else { return }
        do { try audio.configureSession() } catch { dlog("✗ Sesión: \(RingtoneAudioEngine.describe(error))") }
        audio.makeAudible()
        isAudible = true
        onMain(after: 3) { [weak self] in
            guard let self, !self.isArmed else { return }
            self.audio.stop()
            self.isAudible = false
        }
    }

    // MARK: Tono real (iOS 26 "Usar como tono")

    /// Exporta el clip y, si `showShare`, abre Compartir o Vista previa.
    func stageRingtoneFile(showShare: Bool, discreet: Bool) async {
        guard let audio = currentAudio, let track = selected else { return }
        if discreet && Prefs.discreetRingtoneUI { showingDiscreetRingtonePrep = true }

        let t0 = CACurrentMediaTime()
        do {
            let url = try await RingtoneExporter.export(data: audio.data, fileTypeHint: audio.hint,
                                                       title: "\(track.title) - \(track.artist)",
                                                       startAt: Prefs.startOffset)
            exportedRingtone = url
            ringtoneStaged = true
            dlog("Tono preparado en \(PreviewService.ms(since: t0)) ms → \(url.lastPathComponent)")
            attemptRingerVolumeMaxIfEnabled(context: "preparar tono")
            guard showShare else {
                endDiscreetRingtonePrep(discreet)
                return
            }
            presentRingtoneShare(for: track)
            endDiscreetRingtonePrep(discreet)
        } catch {
            dlog("✗ Exportar tono: \(error.localizedDescription)")
            endDiscreetRingtonePrep(discreet)
        }
    }

    @MainActor
    private func endDiscreetRingtonePrep(_ discreet: Bool) {
        guard discreet && Prefs.discreetRingtoneUI else { return }
        DispatchQueue.main.async { self.showingDiscreetRingtonePrep = false }
    }

    func prepareRealRingtone() async {
        await stageRingtoneFile(showShare: true, discreet: true)
    }

    /// Solo abre Compartir si el archivo ya se preparó al buscar la canción.
    func applyRingtoneNow() async {
        guard selected != nil else { return }
        if ringtoneStaged, let url = exportedRingtone, FileManager.default.fileExists(atPath: url.path),
           let track = selected {
            if Prefs.discreetRingtoneUI { showingDiscreetRingtonePrep = true }
            presentRingtoneShare(for: track)
            endDiscreetRingtonePrep(true)
            return
        }
        await stageRingtoneFile(showShare: true, discreet: true)
    }

    @MainActor
    private func presentRingtoneShare(for track: PreviewTrack) {
        guard let url = exportedRingtone else { return }
        let title = "\(track.title) — \(track.artist)"
        if Prefs.ringtoneUseQuickLook {
            RingtoneExporter.presentQuickLook(for: url, displayTitle: title)
        } else {
            RingtoneExporter.presentShareSheet(for: url, displayTitle: title)
        }
    }

    // MARK: Escena

    func arm() {
        guard loadState == .ready else {
            dlog("No se puede armar: no hay canción lista")
            return
        }
        do {
            try audio.configureSession()
        } catch {
            dlog("✗ configureSession: \(RingtoneAudioEngine.describe(error))")
        }
        if Prefs.forceMediaVolume {
            ignoreVolumeChangesUntil = CACurrentMediaTime() + 1
            SystemVolume.shared.set(Float(Prefs.mediaVolumeTarget))
        }
        if Prefs.hotStandby { audio.startStandby() }
        startVolumeButtonWatch()
        isArmed = true
        isAudible = false
        phase = .stage
        UIApplication.shared.isIdleTimerDisabled = true
        dlog("══ ARMADO ══ \(selected.map { "\($0.title) — \($0.artist)" } ?? "?") · \(Prefs.summary())")
    }

    func disarm() {
        SystemVolume.shared.restoreSavedIfNeeded()
        audio.stop()
        audio.deactivateSession()
        volumeObservation = nil
        isArmed = false
        isAudible = false
        phase = .setup
        showDebugOverlay = false
        UIApplication.shared.isIdleTimerDisabled = false
        dlog("══ DESARMADO ══")
    }

    func trigger(source: String) {
        guard isArmed else {
            dlog("Disparo “\(source)” ignorado: no está armado")
            return
        }
        guard !isAudible else {
            dlog("Disparo “\(source)” ignorado: ya suena")
            return
        }
        applySystemVolumeBoostForTrigger()
        let t0 = CACurrentMediaTime()
        let ok = audio.makeAudible()
        isAudible = ok
        let sinceCall = incomingCallID != nil ? " · \(Int((t0 - incomingDetectedAt) * 1000)) ms desde CXCall" : ""
        dlog("▶︎ DISPARO [\(source)] play=\(ok) en \(PreviewService.ms(since: t0)) ms\(sinceCall) · \(audio.snapshot())")
        scheduleHealthChecks(label: source)
    }

    func toggleManual() {
        if isAudible { silence(reason: "toque") } else { trigger(source: "toque") }
    }

    func silence(reason: String) {
        guard isAudible else { return }
        audio.silence()
        isAudible = false
        dlog("■ Silencio [\(reason)]")
    }

    /// Lo que de verdad queremos saber en el iPhone: ¿sigue avanzando el audio con el banner encima?
    private func scheduleHealthChecks(label: String) {
        for delay in [0.3, 1.0, 2.5, 5.0, 9.0] {
            onMain(after: delay) { [weak self] in
                guard let self, self.isArmed else { return }
                dlog("   chequeo +\(delay)s [\(label)] \(self.audio.snapshot())")
            }
        }
    }

    // MARK: Llamadas

    private func handle(_ event: CallMonitor.Event, uuid: UUID) {
        switch event {
        case .incoming:
            incomingCallID = uuid
            incomingDetectedAt = CACurrentMediaTime()
            if isArmed && Prefs.autoTrigger {
                trigger(source: "CXCallObserver")
            } else {
                dlog("Llamada entrante detectada (auto=\(Prefs.autoTrigger), armado=\(isArmed))")
            }
        case .connected:
            if uuid == incomingCallID && Prefs.stopOnAnswer { silence(reason: "contestada") }
        case .ended:
            if uuid == incomingCallID {
                silence(reason: "llamada terminada")
                SystemVolume.shared.restoreSavedIfNeeded()
                incomingCallID = nil
            }
        case .outgoing, .onHold:
            break
        }
    }

    // MARK: Observadores del sistema

    private func installObservers() {
        let nc = NotificationCenter.default
        func observe(_ name: Notification.Name, _ body: @escaping (Notification) -> Void) {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { n in
                MainActor.assumeIsolated { body(n) }
            })
        }

        observe(AVAudioSession.interruptionNotification) { [weak self] n in self?.handleInterruption(n) }
        observe(AVAudioSession.routeChangeNotification) { [weak self] n in
            let raw = n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
            dlog("Ruta cambió (razón \(raw)) → \(RingtoneAudioEngine.routeDescription())")
            if self?.isArmed == true && !RingtoneAudioEngine.isBuiltInSpeaker() {
                dlog("⚠️ Salida fuera del altavoz en escena")
            }
        }
        observe(AVAudioSession.silenceSecondaryAudioHintNotification) { n in
            let raw = n.userInfo?[AVAudioSessionSilenceSecondaryAudioHintTypeKey] as? UInt ?? 99
            dlog("silenceSecondaryAudioHint tipo=\(raw)")
        }
        observe(AVAudioSession.mediaServicesWereResetNotification) { [weak self] _ in
            dlog("⚠️ mediaServicesWereReset: recargando audio")
            guard let self, let track = self.selected else { return }
            Task { await self.select(track) }
        }
        observe(UIApplication.willResignActiveNotification) { _ in dlog("App → willResignActive") }
        observe(UIApplication.didEnterBackgroundNotification) { [weak self] _ in
            dlog("App → didEnterBackground")
            self?.maintainArmedInBackground()
        }
        observe(UIApplication.willEnterForegroundNotification) { [weak self] _ in
            dlog("App → willEnterForeground")
            self?.refreshArmedState(reason: "willEnterForeground")
        }
        observe(UIApplication.didBecomeActiveNotification) { [weak self] _ in
            dlog("App → didBecomeActive")
            self?.refreshArmedState(reason: "didBecomeActive")
        }
        observe(UIApplication.protectedDataWillBecomeUnavailableNotification) { _ in dlog("Dispositivo bloqueado (protectedData no disponible)") }
        observe(UIApplication.protectedDataDidBecomeAvailableNotification) { _ in dlog("Dispositivo desbloqueado (protectedData disponible)") }
    }

    private func handleInterruption(_ n: Notification) {
        guard let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        let reasonRaw = n.userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt
        switch type {
        case .began:
            let wasAudible = isAudible
            isAudible = false
            dlog("⛔️ INTERRUPCIÓN began (razón \(reasonRaw.map(String.init) ?? "nil")) audible antes=\(wasAudible) · \(audio.snapshot())")
        case .ended:
            let optRaw = n.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: optRaw).contains(.shouldResume)
            dlog("✅ INTERRUPCIÓN ended shouldResume=\(shouldResume)")
            ensureStandby()
        @unknown default:
            dlog("Interrupción tipo desconocido \(raw)")
        }
    }

    /// Vuelve a dejar listo audio + pantalla de escena al regresar a la app.
    func refreshArmedState(reason: String) {
        guard isArmed else { return }
        phase = .stage
        UIApplication.shared.isIdleTimerDisabled = true
        do {
            try audio.configureSession()
        } catch {
            dlog("✗ refreshArmedState sesión: \(RingtoneAudioEngine.describe(error))")
        }
        if Prefs.hotStandby {
            if audio.player?.isPlaying != true {
                audio.startStandby()
            } else if !isAudible {
                audio.player?.volume = 0
            }
        }
        syncOngoingIncomingCalls()
        dlog("↻ Re-armado [\(reason)] · \(audio.snapshot()) · CXCall activas=\(calls.currentCalls.count)")
    }

    func maintainArmedInBackgroundIfNeeded() {
        maintainArmedInBackground()
    }

    /// Con `UIBackgroundModes = audio`, mantener el reproductor en vol. 0 ayuda a no ser suspendido.
    private func maintainArmedInBackground() {
        guard isArmed else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            dlog("✗ background setActive: \(RingtoneAudioEngine.describe(error))")
        }
        if Prefs.hotStandby, audio.player?.isPlaying != true {
            audio.startStandby()
            dlog("↻ Standby reiniciado en background")
        } else {
            dlog("Background armado: \(audio.snapshot())")
        }
    }

    /// CXCallObserver a menudo no avisa en segundo plano; al volver, miramos llamadas en curso.
    private func syncOngoingIncomingCalls() {
        for call in calls.currentCalls where !call.isOutgoing && !call.hasConnected && !call.hasEnded {
            if incomingCallID != call.uuid {
                handle(.incoming, uuid: call.uuid)
            } else if Prefs.autoTrigger && !isAudible {
                trigger(source: "CXCall al volver")
            }
        }
    }

    private func ensureStandby() {
        refreshArmedState(reason: "interrupción/standby")
    }

    private func startVolumeButtonWatch() {
        volumeObservation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.old, .new]) { [weak self] _, change in
            onMain(after: 0) {
                guard let self else { return }
                let old = change.oldValue ?? 0
                let new = change.newValue ?? 0
                dlog("Volumen multimedia \(String(format: "%.2f", old)) → \(String(format: "%.2f", new))")
                guard Prefs.volumeButtonTrigger, self.isArmed,
                      CACurrentMediaTime() > self.ignoreVolumeChangesUntil else { return }
                self.ignoreVolumeChangesUntil = CACurrentMediaTime() + 0.6
                SystemVolume.shared.set(old)
                self.toggleManual()
            }
        }
    }

    // MARK: Experimentos

    func runReadOnlyProbes() {
        probeResults = PrivateProbes.runReadOnlyBatch()
    }

    #if MAGIC_PRIVATE_PROBES
    func runToneSet() {
        probeResults = [PrivateProbes.toneLibrarySet(Prefs.toneIdentifierToTry)]
    }

    func runToneRestore() {
        probeResults = [PrivateProbes.toneLibraryRestore()]
    }

    func runRingerVolume(_ value: Float) {
        probeResults = [PrivateProbes.ringtoneVolumeSet(value), PrivateProbes.ringtoneVolumeRead()]
    }

    func runRingerVolumeMax() {
        probeResults = PrivateProbes.ringerVolumeMaxExperiment()
    }
    #endif

    /// Ruta 1: intento opcional de subir el volumen del timbre (API privada; puede no hacer nada).
    private func attemptRingerVolumeMaxIfEnabled(context: String) {
        #if MAGIC_PRIVATE_PROBES
        guard Prefs.attemptRingerMaxOnStage else { return }
        let results = PrivateProbes.ringerVolumeMaxExperiment()
        probeResults = results
        dlog("Ruta 1 [\(context)]: intento volumen timbre al máximo — \(results.map { $0.outcome.rawValue }.joined(separator: ", "))")
        #endif
    }

    /// Ruta 2: sube el volumen multimedia del sistema al 100 % al disparar (llamada o toque manual).
    private func applySystemVolumeBoostForTrigger() {
        guard Prefs.boostSystemVolumeOnTrigger else { return }
        ignoreVolumeChangesUntil = CACurrentMediaTime() + 1.2
        SystemVolume.shared.captureAndBoostToMaximum()
    }

    func scheduleCallKitFallback() {
        CallKitFallback.shared.scheduleIncoming(callerName: Prefs.callKitCallerName, after: Prefs.callKitDelay)
    }
}

private func onMain(after delay: TimeInterval, _ body: @escaping @MainActor () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        MainActor.assumeIsolated(body)
    }
}
