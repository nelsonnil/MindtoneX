import AVFoundation
import CallKit
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
    /// Last track that reached `.ready` in `select()` — survives brief clears before library record.
    private(set) var lastReadyTrack: PreviewTrack?
    /// Last song locked/loaded during Voice Perform — shown on Home after disarm until the next Perform.
    @Published private(set) var performSessionDisplayTrack: PreviewTrack?
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
    private var callPollTimer: Timer?
    private var lastLoggedCallCount = 0
    private var autoTriggerCooldownUntil: CFTimeInterval = 0
    private var callSignalActive = false
    private var hadCallWhileArmed = false
    private(set) var performed = false
    private var currentAudio: (data: Data, hint: String)?
    private var auditionEndWork: DispatchWorkItem?
    private var voicePerformTask: Task<Void, Never>?
    @Published private(set) var exportedRingtone: URL?
    @Published var showingDiscreetRingtonePrep = false
    @Published private(set) var ringtoneStaged = false
    @Published private(set) var voiceOpenAIPreflightInProgress = false
    @Published var voiceOpenAIPreflightAlert: String?

    /// Prevents opening auto-share more than once per Perform.
    var autoSharePresentedThisPerform = false

    @Published var wordSpectatorDialSheet = false
    @Published var wordKnownContactPicker = false

    func setVoiceOpenAIPreflightInProgress(_ inProgress: Bool) {
        voiceOpenAIPreflightInProgress = inProgress
    }

    /// Evita auto-lock mientras la app está visible (setup, Perform, overlays). En background se restaura.
    static func setScreenAwakeWhileInForeground(_ awake: Bool) {
        UIApplication.shared.isIdleTimerDisabled = awake
    }

    private init() {
        #if DEBUG
        FakePostCallVolumeGateSelfTest.run()
        #endif
        Prefs.registerDefaults()
        VoiceSettings.registerDefaults()
        CardSettings.registerDefaults()
        DebugLog.shared.logDeviceHeader()
        calls.onEvent = { [weak self] event, call in
            MainActor.assumeIsolated { self?.handle(event, call: call) }
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

    /// User-picked file from Files (Library → Import audio). App Store–safe: sandbox copy only, no Music library.
    func importAudioFromFiles(_ url: URL) async {
        do {
            let track = try ImportedAudioStore.importTrack(from: url)
            query = track.title
            await select(track)
            dlog("Imported audio: \(track.title) → \(track.previewURL.lastPathComponent)")
        } catch {
            loadState = .failed(error.localizedDescription)
            dlog("✗ Import audio: \(error.localizedDescription)")
        }
    }

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

    /// Library / picker UI — list candidates without auto-loading the first hit.
    func searchForPicker() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        dropPreviewForNewLookup()
        query = q
        results = []
        loadState = .searching
        let t0 = CACurrentMediaTime()
        do {
            let found = try await previews.search(q)
            results = found
            let searchMs = PreviewService.ms(since: t0)
            dlog("[LIBRARY] search “\(q)” → \(found.count) in \(searchMs) ms")
            if found.isEmpty {
                loadState = .failed("No songs found — try different words")
            } else {
                loadState = .idle
            }
        } catch {
            results = []
            loadState = .failed(error.localizedDescription)
            dlog("[LIBRARY] ✗ search “\(q)”: \(error.localizedDescription)")
        }
    }

    /// Drops loaded preview bytes while a new lookup is in flight (AI / Notes / API). Keeps `query`.
    func dropPreviewForNewLookup() {
        audio.unload()
        selected = nil
        currentAudio = nil
        exportedRingtone = nil
        ringtoneStaged = false
        timings = ""
        if case .idle = loadState { return }
        loadState = .idle
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
            lastReadyTrack = track
            SongLibraryStore.shared.recordRecent(track, reason: "select")
            if isArmed { performSessionDisplayTrack = track }
            dlog("Listo: \(track.title) — \(track.artist). \(timings)")
            if isArmed {
                applyFakePerformMediaVolumeBoost(reason: "songReady")
            }
            if Prefs.autoStageRingtone {
                Task { await stageRingtoneFile(showShare: false, discreet: false) }
            }
            if isArmed {
                try? audio.configureSession(preferIPhoneSpeaker: true)
                if Prefs.hotStandby { audio.startStandby() }
                if !isAudible, hasLikelyIncomingCallSignal() {
                    dlog("[TRIGGER] song became ready while a call is ringing")
                    attemptAutoTrigger(source: "songReady.duringCall")
                }
            }
        } catch {
            audio.unload()
            currentAudio = nil
            exportedRingtone = nil
            ringtoneStaged = false
            loadState = .failed(error.localizedDescription)
            if isArmed {
                PerformUserLog.shared.log("Could not load audio · \(error.localizedDescription)")
            }
            dlog("✗ Cargar audio: \(error.localizedDescription)")
        }
    }

    func stopAudition(reason: String = "user") {
        auditionEndWork?.cancel()
        auditionEndWork = nil
        guard isAudible else { return }
        audio.stop()
        audio.recomputeClip()
        isAudible = false
        dlog("Audition stopped [\(reason)]")
    }

    /// Tap play again while auditioning to stop.
    func toggleAudition() {
        if isAudible {
            stopAudition(reason: "toggle")
            return
        }
        audition()
    }

    /// Plays the setup-screen preview for the ringtone window (start offset + up to 28 s), not the old 3 s cap.
    func audition() {
        guard loadState == .ready else { return }
        auditionEndWork?.cancel()
        do { try audio.configureSession(preferIPhoneSpeaker: false) } catch { dlog("✗ Sesión: \(RingtoneAudioEngine.describe(error))") }
        let seconds = audio.configureSetupPreview(maxSeconds: RingtoneLimits.exportMaxSeconds)
        audio.makeAudible(preserveClipBounds: true)
        isAudible = true
        dlog("Audition \(String(format: "%.1f", seconds)) s (ringtone preview window)")
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isArmed else { return }
            self.audio.stop()
            self.audio.recomputeClip()
            self.isAudible = false
        }
        auditionEndWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    // MARK: Tono real (iOS 26 "Usar como tono")

    /// Exporta el clip y, si `showShare`, abre Compartir o Vista previa.
    func stageRingtoneFile(showShare: Bool, discreet: Bool) async {
        guard let audio = currentAudio, let track = selected else { return }
        if discreet && Prefs.discreetRingtoneUI { showingDiscreetRingtonePrep = true }

        let t0 = CACurrentMediaTime()
        do {
            let url = try await RingtoneExporter.export(data: audio.data, fileTypeHint: audio.hint,
                                                       title: track.title, artist: track.artist,
                                                       startAt: Prefs.startOffset,
                                                       maxSeconds: RingtoneLimits.exportMaxSeconds)
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
    /// Fake Ringtone: after hang-up, long-press the stage to open Share (Use as Ringtone).
    func openFakeShareAfterCallIfNeeded() {
        guard FakePostCallShareGate.shouldOpenShareOnLongPress(
            phase: phase,
            performed: performed,
            isArmed: isArmed
        ) else {
            dlog("[SHARE] long-press ignored (Fake post-call only, after hang-up)")
            return
        }
        dlog("[SHARE] long-press post-call → Share ringtone")
        Task { await applyRingtoneNow() }
    }

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

    /// Fake Ringtone: full-screen stage, auto-play on incoming call.
    func performFakeRingtone() {
        arm()
    }

    /// Share Ringtone: export clip and open the system share sheet (Use as Ringtone).
    func performShareRingtone() async {
        guard loadState == .ready, let track = selected else { return }
        if !ringtoneStaged || exportedRingtone == nil
            || !FileManager.default.fileExists(atPath: exportedRingtone?.path ?? "") {
            await stageRingtoneFile(showShare: false, discreet: false)
        }
        guard exportedRingtone != nil else {
            dlog("✗ Share Ringtone: export failed")
            return
        }
        presentRingtoneShare(for: track)
        dlog("Share Ringtone: share sheet presented for Perform")
    }

    /// Library / home ready row: load the track if needed, then export and present Share or Quick Look.
    func shareRingtoneFromLibrary(_ track: PreviewTrack) async {
        if selected?.id != track.id || loadState != .ready {
            query = track.source == .imported ? track.title : "\(track.title) \(track.artist)"
            await select(track)
            guard loadState == .ready, selected?.id == track.id else {
                dlog("✗ Share as ringtone: could not load \(track.title)")
                return
            }
        }
        await performShareRingtone()
        dlog("Share as ringtone: share sheet from library/home for \(track.title)")
    }

    func arm(requireSong: Bool = true) {
        guard loadState == .ready || !requireSong else {
            dlog("No se puede armar: no hay canción lista")
            return
        }
        do {
            try audio.configureSession(preferIPhoneSpeaker: true)
        } catch {
            dlog("✗ configureSession: \(RingtoneAudioEngine.describe(error))")
        }
        applyFakePerformMediaVolumeBoost(reason: "arm")
        if Prefs.forceMediaVolume {
            ignoreVolumeChangesUntil = CACurrentMediaTime() + 1
            SystemVolume.shared.set(Float(Prefs.mediaVolumeTarget), label: "stage target", sliderRetries: 5)
        }
        if Prefs.hotStandby { audio.startStandby() }
        calls.reassertDelegate()
        ensureVolumeButtonWatch()
        if usesCardInput {
            SystemVolume.shared.ensureHeadroomForHardwareVolumeButtons(reason: "Card scan")
        }
        performed = false
        hadCallWhileArmed = false
        autoTriggerCooldownUntil = 0
        startCallPolling()
        isArmed = true
        isAudible = false
        phase = .stage
        Self.setScreenAwakeWhileInForeground(true)
        CallDirectorySync.syncPerformArmed(true, reason: "arm")
        startWordApiIfNeeded(context: .perform)
        PerformUserLog.shared.beginSession(inputLabel: VoiceSettings.inputMode.title)
        CallDirectorySync.reportPerformReadiness()
        dlog("══ ARMADO ══ \(selected.map { "\($0.title) — \($0.artist)" } ?? "?") · \(Prefs.summary())")
    }

    func disarm() {
        dlog("[LIBRARY] disarm begin · selected=\(selected?.title ?? "nil") lastReady=\(lastReadyTrack?.title ?? "nil") lockedPick=\(VoiceSongSession.shared.lockedPick?.label ?? "nil") recent=\(SongLibraryStore.shared.recent.count)")
        stopCallPolling()
        callSignalActive = false
        SystemVolume.shared.restoreSavedIfNeeded()
        volumeObservation = nil
        voicePerformTask?.cancel()
        voicePerformTask = nil
        showDebugOverlay = false
        performed = false
        hadCallWhileArmed = false
        isAudible = false
        resetVoicePerformance()
        audio.stop()
        audio.deactivateSession()
        isArmed = false
        phase = .setup
        CallDirectorySync.syncPerformArmed(false, reason: "disarm")
        if let track = performSessionDisplayTrack {
            SongLibraryStore.shared.syncFromPerformDisplay(track, reason: "disarm")
        }
        clearPerformSessionDisplayTrack()
        SongLibraryStore.shared.reloadFromDisk()
        SongLibraryStore.shared.logRecentDisplayMerge(context: "disarm")
        PerformUserLog.shared.endSession()
        dlog("══ DESARMADO ══")
    }

    func notePerformDisplayTrack() {
        if let track = selected ?? lastReadyTrack {
            performSessionDisplayTrack = track
            dlog("[LIBRARY] perform display track “\(track.title) — \(track.artist)”")
        }
    }

    func clearPerformSessionDisplayTrack() {
        performSessionDisplayTrack = nil
    }

    func commitVoicePerformSnapshotIfNeeded(reason: String) {
        guard usesVoiceInput else { return }
        guard let pick = VoiceSongSession.shared.lockedPick else {
            dlog("[LIBRARY] \(reason) — no lockedPick · selected=\(selected?.title ?? "nil") lastReady=\(lastReadyTrack?.title ?? "nil") loadState=\(loadState)")
            return
        }
        let preview = selected?.previewURL.absoluteString ?? lastReadyTrack?.previewURL.absoluteString
        SongLibraryStore.shared.commitPerformSnapshot(
            RecentPerformSnapshot(pick: pick, previewURL: preview)
        )
        notePerformDisplayTrack()
        dlog("[LIBRARY] \(reason) snapshot committed · display=\(performSessionDisplayTrack?.title ?? "nil")")
    }

    func scheduleVoicePerformStart() {
        voicePerformTask?.cancel()
        voicePerformTask = Task { await VoiceSongSession.shared.start(context: .perform) }
    }

    /// Home sheets / call banner: stop Live preview mic before AVAudioSession changes.
    func pauseVoiceAndAudioForSetupUI(reason: String) {
        guard phase == .setup, !isArmed else { return }
        voicePerformTask?.cancel()
        voicePerformTask = nil
        VoiceSongSession.shared.stopTest()
        ApiSongSession.shared.stopTest()
        auditionEndWork?.cancel()
        auditionEndWork = nil
        if isAudible {
            audio.stop()
            isAudible = false
        }
        VoiceAudioSession.recordCategoryActive = false
        VoiceAudioSession.deactivateIfIdle()
        dlog("[APP] paused setup audio/voice (\(reason))")
    }

    /// After the spectator hangs up in Fake Ringtone: stop playback, allow long-press → Share, stay on
    /// stage armed for another call with the same locked song. Share Ringtone Perform is unaffected.
    private func enterPerformedState(reason: String) {
        guard isArmed, !performed else { return }
        performed = true
        callSignalActive = false
        incomingCallID = nil
        incomingDetectedAt = 0
        hadCallWhileArmed = false
        autoTriggerCooldownUntil = 0
        audio.stop()
        audio.player?.currentTime = 0
        isAudible = false
        SystemVolume.shared.restoreSavedIfNeeded()
        audio.deactivateSession()
        if Prefs.hotStandby, loadState == .ready {
            do { try audio.configureSession(preferIPhoneSpeaker: true) } catch {
                dlog("✗ post-call standby sesión: \(RingtoneAudioEngine.describe(error))")
            }
            audio.startStandby()
        }
        ensureVolumeButtonWatch()
        recordRecentLoadedSongIfReady(reason: "performed:\(reason)")
        dlog("[TRIGGER] ■ PERFORMED (\(reason)) — playback stopped; long-press stage → Share; armed for next call. Leave Perform (two-finger swipe down) to reset.")
    }

    /// Manual search only — Voice/Notes/API songs live in Library (Recently used / Favorites).
    var displayLoadedTrack: PreviewTrack? {
        guard VoiceSettings.inputMode == .manual else { return nil }
        guard let track = selected, loadState == .ready else { return nil }
        return track
    }

    /// Library → Recently used (deduped in `SongLibraryStore`).
    func recordRecentLoadedSongIfReady(reason: String = "ifReady") {
        guard let track = selected ?? lastReadyTrack else {
            dlog("[LIBRARY] skip record (\(reason)): no track · loadState=\(loadState)")
            return
        }
        guard loadState == .ready || lastReadyTrack != nil else {
            dlog("[LIBRARY] skip record (\(reason)): loadState=\(loadState)")
            return
        }
        if isArmed, findsSongDuringPerform {
            SongLibraryStore.shared.commitPerformTrack(track, reason: reason)
        } else {
            SongLibraryStore.shared.recordRecent(track, reason: reason)
        }
    }

    /// AI Voice: forget the previous spectator's song so the next Perform starts empty.
    func clearSongForNextPerformance() {
        if let track = selected ?? lastReadyTrack {
            SongLibraryStore.shared.commitPerformTrack(track, reason: "clearForNextPerform")
        }
        audio.unload()
        query = ""
        results = []
        selected = nil
        currentAudio = nil
        exportedRingtone = nil
        ringtoneStaged = false
        timings = ""
        loadState = .idle
        lastReadyTrack = nil
        dlog("Canción descartada — el próximo Perform empieza vacío hasta nueva búsqueda/bloqueo")
    }

    func trigger(source: String) {
        VoiceSongSession.shared.callArrived(source: source)
        NotesSongSession.shared.callArrived(source: source)
        ApiSongSession.shared.callArrived(source: source)
        CardSongSession.shared.callArrived(source: source)
        guard isArmed else {
            dlog("[TRIGGER] “\(source)” ignorado: no armado")
            return
        }
        guard !performed else {
            dlog("[TRIGGER] “\(source)” ignorado: post-llamada (long-press → Compartir o nueva llamada)")
            return
        }
        guard !isAudible else {
            dlog("[TRIGGER] “\(source)” ignorado: ya audible")
            return
        }
        guard loadState == .ready, currentAudio != nil else {
            dlog("[TRIGGER] “\(source)” ignorado: sin canción para este Perform (elige o deja que se bloquee una nueva)")
            return
        }
        if findsSongDuringPerform, !hasSongLockedForCurrentPerform() {
            dlog("[TRIGGER] “\(source)” ignorado: canción aún no bloqueada en este Perform")
            return
        }
        applySystemVolumeBoostForTrigger()
        let t0 = CACurrentMediaTime()
        logAudioSession(context: "antes de disparo [\(source)]")
        let ok = audio.makeAudible(reconfigureSession: { try self.audio.configureSession(preferIPhoneSpeaker: true) })
        isAudible = ok
        let sinceCall = callSignalActive ? " · \(Int((t0 - incomingDetectedAt) * 1000)) ms desde señal llamada" : ""
        dlog("[TRIGGER] ▶︎ [\(source)] play=\(ok)\(sinceCall) · \(audio.snapshot())")
        if !ok { schedulePlayRetries(origin: source) }
        scheduleHealthChecks(label: source)
    }

    /// Disparo automático (CXCall, interrupción, ruta, sondeo…).
    private func attemptAutoTrigger(source: String) {
        guard isArmed, Prefs.autoTrigger else {
            dlog("[AUTO] \(source) no dispara (arm=\(isArmed) auto=\(Prefs.autoTrigger))")
            return
        }
        if isAudible {
            dlog("[AUTO] \(source) no dispara: ya audible")
            return
        }
        let now = CACurrentMediaTime()
        if now < autoTriggerCooldownUntil {
            dlog("[AUTO] \(source) en cooldown \(Int((autoTriggerCooldownUntil - now) * 1000)) ms")
            return
        }
        autoTriggerCooldownUntil = now + 0.2
        if incomingDetectedAt == 0 { incomingDetectedAt = now }
        callSignalActive = true
        dlog("[AUTO] → trigger desde \(source)")
        trigger(source: source)
    }

    func toggleManual() {
        if isAudible { silence(reason: "toque") } else { trigger(source: "toque") }
    }

    func silence(reason: String) {
        guard isAudible else { return }
        audio.silence(holdUntilExplicitPlay: true)
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

    private func handle(_ event: CallMonitor.Event, call: CXCall) {
        let uuid = call.uuid
        noteWordContactCallEvent(event, uuid: uuid, call: call)
        switch event {
        case .incoming:
            guard isArmed else {
                dlog("[TRIGGER] CXCall incoming ignored: not armed\(performed ? " (performed — waiting for exit)" : "")")
                return
            }
            if performed {
                performed = false
                dlog("[TRIGGER] new incoming call in Perform — replay same locked song")
            }
            incomingCallID = uuid
            incomingDetectedAt = CACurrentMediaTime()
            callSignalActive = true
            hadCallWhileArmed = true
            PerformUserLog.shared.log("Incoming call detected")
            VoiceSongSession.shared.callArrived(source: "CXCallObserver.incoming")
            NotesSongSession.shared.callArrived(source: "CXCallObserver.incoming")
            ApiSongSession.shared.callArrived(source: "CXCallObserver.incoming")
            CardSongSession.shared.callArrived(source: "CXCallObserver.incoming")
            attemptAutoTrigger(source: "CXCallObserver.incoming")
        case .connected:
            if uuid == incomingCallID && Prefs.stopOnAnswer { silence(reason: "contestada") }
        case .ended:
            let wasOurs = uuid == incomingCallID
            if isArmed && (wasOurs || isAudible || hadCallWhileArmed || callSignalActive) {
                enterPerformedState(reason: "CXCall ended (ours=\(wasOurs))")
            }
            if wasOurs {
                incomingCallID = nil
                callSignalActive = false
                incomingDetectedAt = 0
            }
            if calls.currentCalls.allSatisfy(\.hasEnded) {
                callSignalActive = false
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
            guard let self else { return }
            let raw = n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
            let prev = n.userInfo?[AVAudioSessionRouteChangePreviousRouteKey]
            dlog("[ROUTE] cambió reason=\(raw) prev=\(prev != nil) → \(RingtoneAudioEngine.routeDescription()) · \(self.calls.describeCalls())")
            if self.isArmed {
                RingtoneAudioEngine.applyBuiltInSpeakerOverride(reason: "routeChange(\(raw))")
            }
            if self.isArmed, self.hasLikelyIncomingCallSignal() {
                self.attemptAutoTrigger(source: "routeChange(\(raw))")
            }
        }
        observe(AVAudioSession.silenceSecondaryAudioHintNotification) { [weak self] n in
            guard let self else { return }
            let raw = n.userInfo?[AVAudioSessionSilenceSecondaryAudioHintTypeKey] as? UInt ?? 99
            dlog("[AUDIO] silenceSecondaryAudioHint=\(raw) · \(self.audio.snapshot())")
            // 0 = begin (silenciar secundario), 1 = end
            if self.isArmed, raw == 0 {
                self.attemptAutoTrigger(source: "silenceSecondaryAudioHint.begin")
            }
        }
        observe(AVAudioSession.mediaServicesWereResetNotification) { [weak self] _ in
            dlog("⚠️ mediaServicesWereReset: recargando audio")
            guard let self, let track = self.selected else { return }
            Task { await self.select(track) }
        }
        observe(UIApplication.willResignActiveNotification) { _ in dlog("App → willResignActive") }
        observe(UIApplication.didEnterBackgroundNotification) { [weak self] _ in
            dlog("App → didEnterBackground")
            Self.setScreenAwakeWhileInForeground(false)
            self?.maintainArmedInBackground()
        }
        observe(UIApplication.willEnterForegroundNotification) { [weak self] _ in
            dlog("App → willEnterForeground")
            self?.refreshArmedState(reason: "willEnterForeground")
        }
        observe(UIApplication.didBecomeActiveNotification) { [weak self] _ in
            dlog("App → didBecomeActive")
            Self.setScreenAwakeWhileInForeground(true)
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
            logAudioSession(context: "interruption.began reason=\(reasonRaw.map(String.init) ?? "nil")")
            dlog("[AUDIO] ⛔️ interruption.began audibleAntes=\(wasAudible) · \(audio.snapshot()) · \(calls.describeCalls())")
            isAudible = false
            guard isArmed else {
                dlog("[AUDIO] interruption.began: not armed\(performed ? " (performed)" : "") → no standby, no trigger")
                return
            }
            audio.markStandbyAfterInterruption()
            callSignalActive = true
            incomingDetectedAt = CACurrentMediaTime()
            attemptAutoTrigger(source: "interruption.began")
        case .ended:
            let optRaw = n.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: optRaw).contains(.shouldResume)
            dlog("[AUDIO] ✅ interruption.ended shouldResume=\(shouldResume) (never auto-resumed) · \(calls.describeCalls())")
            guard isArmed else {
                dlog("[AUDIO] interruption.ended: not armed\(performed ? " (performed)" : "") → ignored")
                return
            }
            if hadCallWhileArmed, calls.currentCalls.allSatisfy(\.hasEnded) {
                enterPerformedState(reason: "interruption.ended with no active call")
            } else if !calls.ringingIncomingCalls().isEmpty, !isAudible {
                dlog("[TRIGGER] interruption.ended while a call is still ringing → trigger")
                attemptAutoTrigger(source: "interruption.ended")
            } else {
                dlog("[AUDIO] interruption.ended: no ringing call → standby only")
                ensureStandby()
            }
        @unknown default:
            dlog("[AUDIO] interruption tipo=\(raw)")
        }
    }

    /// Vuelve a dejar listo audio + pantalla de escena al regresar a la app.
    func refreshArmedState(reason: String) {
        guard isArmed else { return }
        phase = .stage
        Self.setScreenAwakeWhileInForeground(true)
        do {
            try audio.configureSession(preferIPhoneSpeaker: true)
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
        calls.reassertDelegate()
        syncOngoingIncomingCalls()
        dlog("[APP] ↻ re-armado [\(reason)] · \(audio.snapshot()) · CXCall=\(calls.describeCalls())")
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
        let ringing = calls.ringingIncomingCalls()
        if !ringing.isEmpty {
            callSignalActive = true
            if incomingDetectedAt == 0 { incomingDetectedAt = CACurrentMediaTime() }
        }
        for call in ringing {
            if incomingCallID != call.uuid {
                handle(.incoming, call: call)
            } else if !isAudible {
                attemptAutoTrigger(source: "CXCall.sync")
            }
        }
    }

    private func hasLikelyIncomingCallSignal() -> Bool {
        !calls.ringingIncomingCalls().isEmpty || callSignalActive
    }

    func onSceneBecameInactive() {
        dlog("[APP] scenePhase inactive · \(calls.describeCalls()) · \(audio.snapshot())")
        guard isArmed else { return }
        calls.reassertDelegate()
        syncOngoingIncomingCalls()
        if hasLikelyIncomingCallSignal() {
            attemptAutoTrigger(source: "scenePhase.inactive")
        }
    }

    private func startCallPolling() {
        stopCallPolling()
        let timer = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollCallsWhileArmed() }
        }
        RunLoop.main.add(timer, forMode: .common)
        callPollTimer = timer
        dlog("[CXCall] sondeo cada 350 ms mientras armado")
    }

    private func stopCallPolling() {
        callPollTimer?.invalidate()
        callPollTimer = nil
        lastLoggedCallCount = 0
    }

    private func pollCallsWhileArmed() {
        guard isArmed else { return }
        let count = calls.currentCalls.count
        if count != lastLoggedCallCount {
            dlog("[CXCall] poll count \(lastLoggedCallCount)→\(count) · \(calls.describeCalls()) app=\(appStateLabel())")
            lastLoggedCallCount = count
        }
        if !calls.ringingIncomingCalls().isEmpty { hadCallWhileArmed = true }
        if hadCallWhileArmed, calls.currentCalls.allSatisfy(\.hasEnded) {
            enterPerformedState(reason: "CXCall.poll: call gone")
            return
        }
        syncOngoingIncomingCalls()
        if !calls.ringingIncomingCalls().isEmpty, !isAudible {
            attemptAutoTrigger(source: "CXCall.poll")
        }
    }

    private func appStateLabel() -> String {
        switch UIApplication.shared.applicationState {
        case .active: return "active"
        case .inactive: return "inactive"
        case .background: return "background"
        @unknown default: return "?"
        }
    }

    private func logAudioSession(context: String) {
        let s = AVAudioSession.sharedInstance()
        dlog("[AUDIO] \(context) cat=\(s.category.rawValue) active otherAudio=\(s.isOtherAudioPlaying) secondarySilenceHint=\(s.secondaryAudioShouldBeSilencedHint) outVol=\(String(format: "%.2f", s.outputVolume))")
    }

    private func schedulePlayRetries(origin: String) {
        for delay in [0.1, 0.28, 0.55] {
            onMain(after: delay) { [weak self] in
                guard let self, self.isArmed, !self.isAudible else { return }
                guard self.hasLikelyIncomingCallSignal() || origin.contains("toque") else { return }
                self.autoTriggerCooldownUntil = 0
                dlog("[TRIGGER] reintento +\(delay)s [\(origin)]")
                self.trigger(source: "\(origin).retry")
            }
        }
    }

    private func ensureStandby() {
        refreshArmedState(reason: "interrupción/standby")
    }

    private func ensureVolumeButtonWatch() {
        guard volumeObservation == nil else { return }
        volumeObservation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.old, .new]) { [weak self] _, change in
            onMain(after: 0) {
                guard let self else { return }
                let old = change.oldValue ?? 0
                let new = change.newValue ?? 0
                dlog("Volumen multimedia \(String(format: "%.2f", old)) → \(String(format: "%.2f", new))")
                if CardSongSession.shared.capturesVolumeButtons {
                    self.ignoreVolumeChangesUntil = CACurrentMediaTime() + 0.55
                    SystemVolume.shared.set(old, label: "card scan revert")
                    CardSongSession.shared.volumeScanTriggered()
                    return
                }
                guard CACurrentMediaTime() > self.ignoreVolumeChangesUntil else { return }
                guard FakePostCallVolumeGate.shouldTogglePlayOnVolume(
                    volumeButtonTrigger: Prefs.volumeButtonTrigger,
                    isArmed: self.isArmed,
                    performed: self.performed,
                    cardCaptureUsesVolume: false
                ) else { return }
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

    /// Fake Ringtone: best-effort max media volume via hidden `MPVolumeView` (public API; slider hook undocumented).
    func applyFakePerformMediaVolumeBoost(reason: String) {
        guard Prefs.boostMediaVolumeOnFakePerform else { return }
        ignoreVolumeChangesUntil = CACurrentMediaTime() + 1.2
        let target = Float(Prefs.fakePlaybackVolume)
        let before = SystemVolume.shared.outputVolume
        SystemVolume.shared.set(target, label: "fake playback (\(reason))", sliderRetries: 5)
        dlog("[VOLUME] Fake Perform (\(reason)) target=\(String(format: "%.2f", target)) before=\(String(format: "%.2f", before)) attached=\(SystemVolume.shared.isAttached)")
    }

    /// Ruta 2: sube el volumen multimedia del sistema al 100 % al disparar (llamada o toque manual).
    private func applySystemVolumeBoostForTrigger() {
        guard Prefs.boostSystemVolumeOnTrigger else { return }
        ignoreVolumeChangesUntil = CACurrentMediaTime() + 1.2
        SystemVolume.shared.set(Float(Prefs.fakePlaybackVolume), label: "fake trigger", sliderRetries: 5)
    }

}

private func onMain(after delay: TimeInterval, _ body: @escaping @MainActor () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        MainActor.assumeIsolated(body)
    }
}
