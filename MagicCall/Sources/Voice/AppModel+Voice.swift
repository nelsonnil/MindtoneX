import Foundation
import UIKit

extension AppModel {
    var usesVoiceInput: Bool { VoiceSettings.inputMode == .aiVoice }
    var usesNotesInput: Bool { VoiceSettings.inputMode == .notes }
    var usesApiInput: Bool { VoiceSettings.inputMode == .api }
    var usesCardInput: Bool { VoiceSettings.inputMode == .card }
    /// AI Voice, Notes, API and Card find the song during Perform, so each Perform starts with no song.
    var findsSongDuringPerform: Bool { usesVoiceInput || usesNotesInput || usesApiInput || usesCardInput }

    /// Auto-share on song lock applies only to inputs that lock during Perform (not Manual on Home).
    var inputSupportsAutoShareOnSongLock: Bool {
        switch VoiceSettings.inputMode {
        case .manual: return false
        case .aiVoice, .notes, .api, .card: return true
        }
    }

    /// True when this Perform may play audio (locked or manual track loaded after reset).
    func hasSongLockedForCurrentPerform() -> Bool {
        switch VoiceSettings.inputMode {
        case .aiVoice: return VoiceSongSession.shared.state == .locked
        case .notes: return NotesSongSession.shared.isLocked
        case .api: return ApiSongSession.shared.state == .locked
        case .card: return CardSongSession.shared.isLocked
        case .manual: return loadState == .ready
        }
    }

    /// Perform for all song inputs — enters stage/call audio directly (no Silent Shortcut preamble).
    func perform() {
        guard !voiceOpenAIPreflightInProgress else { return }

        if OpenAIPerformRequirements.requiresKeyBeforePerform, !VoiceSettings.isConfigured {
            openAIMissingKeySheet = true
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }

        if OpenAIPerformRequirements.requiresKeyBeforePerform {
            setVoiceOpenAIPreflightInProgress(true)
            Task {
                defer { setVoiceOpenAIPreflightInProgress(false) }
                if let message = await VoiceOpenAIPreflight.checkBeforePerform() {
                    voiceOpenAIPreflightAlert = message
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    return
                }
                performNow()
            }
            return
        }
        performNow()
    }

    private func performNow() {
        if isArmed {
            dlog("══ PERFORM ══ already armed → disarm and start fresh")
            disarm()
        }
        let input = VoiceSettings.inputMode
        dlog("══ PERFORM ══ input=\(input.title)")
        let apiLiveWatchHandoff = ApiSongSession.shared.liveWatchBaselineForPerformHandoff()
        if findsSongDuringPerform {
            clearPerformSessionDisplayTrack()
            VoiceSongSession.shared.reset(reason: "new Perform")
            NotesSongSession.shared.reset(reason: "new Perform")
            ApiSongSession.shared.reset(reason: "new Perform")
            CardSongSession.shared.reset(reason: "new Perform")
            WordApiSession.shared.reset(reason: "new Perform")
            NotesContactWordSession.shared.reset(reason: "new Perform")
            SecondSpectatorSong.shared.reset(reason: "new Perform")
            clearSongForNextPerformance()
        }
        guard StageImageStore.hasScreenshot else {
            dlog("══ PERFORM ══ blocked: no stage screenshot")
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        pendingApiLiveWatchHandoff = apiLiveWatchHandoff
        runPerformWithWordContactPrep()
    }

    func performNowAfterWordContactPrep() {
        resetAutoSharePresentedFlag()
        let input = VoiceSettings.inputMode
        let apiHandoff = pendingApiLiveWatchHandoff
        pendingApiLiveWatchHandoff = nil
        if SpectatorSettings.isTwo, findsSongDuringPerform {
            SecondSpectatorSong.shared.beginWaiting(source: input.title, context: .perform)
        }
        switch input {
        case .aiVoice:
            VoiceAudioSession.recordCategoryActive = true
            arm(requireSong: false)
            scheduleVoicePerformStart()
        case .notes:
            NotesSongSession.shared.start(context: .perform)
            arm(requireSong: false)
        case .api:
            arm(requireSong: false)
            ApiSongSession.shared.start(context: .perform, liveWatchHandoff: apiHandoff)
        case .card:
            CardSongSession.shared.start(context: .perform)
            arm(requireSong: false)
            dlog("[CARD] Perform entered · camera idle until volume press · vol=\(String(format: "%.2f", SystemVolume.shared.outputVolume))")
            PerformUserLog.shared.log("Camera · ready — press **volume up** to scan · **volume down** after call → Share ringtone")
        case .manual:
            performFakeRingtone()
        }
    }

    var canPerform: Bool {
        let inputReady: Bool = switch VoiceSettings.inputMode {
        case .aiVoice:
            VoiceSettings.isConfigured
        case .notes:
            !OpenAIPerformRequirements.requiresKeyBeforePerform || VoiceSettings.isConfigured
        case .api:
            ApiSettings.isConfigured
        case .card:
            CardSettings.cameraAuthorized
                && (!OpenAIPerformRequirements.requiresKeyBeforePerform || VoiceSettings.isConfigured)
        case .manual:
            loadState == .ready
        }
        return inputReady && StageImageStore.hasScreenshot
    }

    /// Looks up and loads a voice candidate with the normal preview lookup.
    func prepareVoiceCandidate(_ pick: SongPick) async -> Bool {
        await prepareSongQuery(pick.searchQuery)
    }

    /// Looks up and loads the song written in Notes with the normal preview lookup.
    func prepareNotesQuery(_ query: String) async -> Bool {
        await prepareSongQuery(query)
    }

    /// Looks up and loads the spectator's search read from the API with the normal preview lookup.
    func prepareApiQuery(_ query: String) async -> Bool {
        await prepareSongQuery(query)
    }

    func prepareCardQuery(_ query: String) async -> Bool {
        await prepareSongQuery(query)
    }

    private func prepareSongQuery(_ text: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        dropPreviewForNewLookup()
        query = trimmed
        await search()
        guard loadState == .ready else { return false }
        return true
    }

    func voiceDidLock(context: VoiceSongSession.Context, duringCall: Bool) {
        if !duringCall {
            if isArmed {
                do { try audio.configureSession(preferIPhoneSpeaker: isArmed) } catch {
                    dlog("✗ [VOICE] back to playback: \(RingtoneAudioEngine.describe(error))")
                }
                if Prefs.hotStandby, audio.player != nil, audio.player?.isPlaying != true { audio.startStandby() }
                dlog("[VOICE] audio back to playback · \(audio.snapshot())")
            } else {
                VoiceAudioSession.deactivateIfIdle()
            }
        }
        if context == .perform, isArmed {
            applyFakePerformMediaVolumeBoost(reason: "songLocked")
        }
        if context == .perform {
            recordRecentLoadedSongIfReady(reason: "voiceDidLock")
            autoShareOnSongLockIfEnabled(source: "Voice")
            albumArtOnContactIfEnabled(source: "Voice")
        }
    }

    /// Spectators = 2: song 1 locked while the mic stays on for spectator 2 — no audio-session switch yet.
    func voiceFirstOfTwoLocked(context: VoiceSongSession.Context) {
        guard context == .perform else { return }
        recordRecentLoadedSongIfReady(reason: "voiceFirstOfTwo")
        if isArmed {
            applyFakePerformMediaVolumeBoost(reason: "songLocked")
        }
        albumArtOnContactIfEnabled(source: "Voice · song 1")
    }

    func notesSongReady(context: NotesSongSession.Context) {
        guard context == .perform else { return }
        recordRecentLoadedSongIfReady(reason: "notesReady")
        if isArmed {
            applyFakePerformMediaVolumeBoost(reason: "notesReady")
        }
        autoShareOnSongLockIfEnabled(source: "Notes")
        albumArtOnContactIfEnabled(source: "Notes")
    }

    func apiSongLocked(context: ApiSongSession.Context) {
        if context == .perform {
            recordRecentLoadedSongIfReady(reason: "apiLocked")
        }
        if context == .perform, isArmed {
            applyFakePerformMediaVolumeBoost(reason: "apiLocked")
        }
        if context == .perform {
            autoShareOnSongLockIfEnabled(source: "API")
            albumArtOnContactIfEnabled(source: "API")
        }
    }

    func cardSongLocked(context: CardSongSession.Context) {
        if context == .perform {
            recordRecentLoadedSongIfReady(reason: "cardLocked")
        }
        if context == .perform, isArmed {
            applyFakePerformMediaVolumeBoost(reason: "cardLocked")
        }
        if context == .perform {
            autoShareOnSongLockIfEnabled(source: "Card")
            albumArtOnContactIfEnabled(source: "Card")
        }
    }

    func albumArtOnContactIfEnabled(source: String) {
        guard AlbumArtContactSettings.enabled, isArmed else { return }
        if source.localizedCaseInsensitiveContains("song 2") { return }
        guard loadState == .ready, let track = selected ?? lastReadyTrack else { return }
        AlbumArtContactService.applyOnSongLock(track: track, reason: source)
    }

    /// Leaving Perform starts the next performance from zero (no stale song on the next run).
    func resetVoicePerformance() {
        SharePerformFlow.shared.reset()
        resetAutoSharePresentedFlag()
        commitVoicePerformSnapshotIfNeeded(reason: "resetVoicePerformance")
        recordRecentLoadedSongIfReady(reason: "leftPerform")
        VoiceSongSession.shared.reset(reason: "left Perform")
        NotesSongSession.shared.reset(reason: "left Perform")
        ApiSongSession.shared.reset(reason: "left Perform")
        CardSongSession.shared.reset(reason: "left Perform")
        WordApiSession.shared.reset(reason: "left Perform")
        NotesContactWordSession.shared.reset(reason: "left Perform")
        SecondSpectatorSong.shared.abandon(reason: "left Perform")
        clearSongForNextPerformance()
    }

    func startWordApiIfNeeded(context: WordApiSession.Context) {
        guard WordApiSettings.callerLabelEnabled, WordApiSettings.hasWordEndpoint else { return }
        WordApiSession.shared.start(context: context)
    }

    func startNotesContactWordIfNeeded(context: NotesContactWordSession.Context) {
        guard NotesContactWordSettings.isConfigured else { return }
        NotesContactWordSession.shared.start(context: context)
    }

    /// Home screen: switching song input must not leave a preview loaded from AI Voice / Notes / API Test.
    func resetAfterSongInputModeChange(from previous: VoiceSettings.InputMode, to next: VoiceSettings.InputMode) {
        guard previous != next else { return }
        VoiceSongSession.shared.reset(reason: "input mode \(previous.title) → \(next.title)")
        NotesSongSession.shared.reset(reason: "input mode")
        ApiSongSession.shared.reset(reason: "input mode")
        CardSongSession.shared.reset(reason: "input mode")
        SecondSpectatorSong.shared.reset(reason: "input mode")
        WordApiSession.shared.stopTest()
        NotesContactWordSession.shared.stopTest()
        if previous != .manual || next != .manual {
            clearSongForNextPerformance()
        }
    }

    // MARK: Auto-share on song lock

    func resetAutoSharePresentedFlag() {
        autoSharePresentedThisPerform = false
    }

    func autoShareOnSongLockIfEnabled(source: String) {
        guard Prefs.autoShareOnSongLock, isArmed, phase == .stage, !autoSharePresentedThisPerform else { return }
        guard loadState == .ready else { return }
        if SecondSpectatorSong.shared.isPendingInPerform {
            dlog("[AUTO-SHARE] song locked (\(source)) · waiting for spectator 2 before Share")
            return
        }
        autoSharePresentedThisPerform = true
        dlog("[AUTO-SHARE] song locked (\(source)) → Share sheet")
        Task { await presentShareDuringPerform() }
    }

    private func presentShareDuringPerform() async {
        let voice = VoiceSongSession.shared
        if voice.isActive { voice.reset(reason: "auto-share") }
        if ApiSongSession.shared.isActive { ApiSongSession.shared.stopTest() }
        VoiceAudioSession.recordCategoryActive = false
        VoiceAudioSession.deactivateIfIdle()
        guard loadState == .ready else { return }
        var waited = 0
        while Prefs.autoStageRingtone, !ringtoneStaged, waited < 40 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            waited += 1
        }
        await performShareRingtone()
    }
}
