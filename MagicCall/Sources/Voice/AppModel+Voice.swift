import Foundation
import UIKit

extension AppModel {
    var usesVoiceInput: Bool { VoiceSettings.inputMode == .aiVoice }
    var usesNotesInput: Bool { VoiceSettings.inputMode == .notes }
    var usesApiInput: Bool { VoiceSettings.inputMode == .api }
    /// AI Voice, Notes and API find the song during Perform, so each Perform starts with no song.
    var findsSongDuringPerform: Bool { usesVoiceInput || usesNotesInput || usesApiInput }

    /// True when this Perform may play audio (locked or manual track loaded after reset).
    func hasSongLockedForCurrentPerform() -> Bool {
        switch VoiceSettings.inputMode {
        case .aiVoice: return VoiceSongSession.shared.state == .locked
        case .notes: return NotesSongSession.shared.isLocked
        case .api: return ApiSongSession.shared.state == .locked
        case .manual: return loadState == .ready
        }
    }

    /// Perform button for both modes and all song inputs. Runs the Silent On/Off Shortcut first
    /// when enabled, and continues when Shortcuts returns to the app.
    func perform() {
        let mode = Prefs.performanceMode
        if SilentShortcut.isEnabled(for: mode) {
            SilentShortcut.shared.runBeforePerform(mode: mode) { [weak self] in self?.performNow() }
        } else {
            performNow()
        }
    }

    private func performNow() {
        if isArmed {
            dlog("══ PERFORM ══ already armed → disarm and start fresh")
            disarm()
        }
        let input = VoiceSettings.inputMode
        dlog("══ PERFORM ══ mode=\(Prefs.performanceMode.title) input=\(input.title)")
        if findsSongDuringPerform {
            VoiceSongSession.shared.reset(reason: "new Perform")
            NotesSongSession.shared.reset(reason: "new Perform")
            ApiSongSession.shared.reset(reason: "new Perform")
            clearSongForNextPerformance()
        }
        switch Prefs.performanceMode {
        case .fakeRingtone:
            switch input {
            case .aiVoice:
                VoiceAudioSession.recordCategoryActive = true
                arm(requireSong: false)
                Task { await VoiceSongSession.shared.start(context: .perform) }
            case .notes:
                NotesSongSession.shared.start(context: .perform)
                arm(requireSong: false)
            case .api:
                arm(requireSong: false)
                ApiSongSession.shared.start(context: .perform)
            case .manual:
                performFakeRingtone()
            }
        case .shareRingtone:
            SharePerformFlow.shared.start(input: input)
        }
    }

    var canPerform: Bool {
        switch VoiceSettings.inputMode {
        case .aiVoice: return VoiceSettings.isConfigured
        case .notes: return true
        case .api: return ApiSettings.isConfigured
        case .manual: return loadState == .ready
        }
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

    private func prepareSongQuery(_ text: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != query.trimmingCharacters(in: .whitespacesAndNewlines) || loadState == .ready {
            dropPreviewForNewLookup()
        }
        query = trimmed
        await search()
        guard loadState == .ready else { return false }
        if Prefs.performanceMode == .shareRingtone, !Prefs.autoStageRingtone {
            await stageRingtoneFile(showShare: false, discreet: false)
        }
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
        if context == .perform, Prefs.performanceMode == .fakeRingtone, isArmed {
            applyFakePerformMediaVolumeBoost(reason: "songLocked")
        }
        if context == .perform, SharePerformFlow.shared.isActive {
            SharePerformFlow.shared.songLocked()
        }
    }

    /// Notes found and loaded a song. Fake Ringtone keeps it hot (select() already restarted
    /// standby); Share Ringtone opens the Share sheet with it.
    func notesSongReady(context: NotesSongSession.Context) {
        guard context == .perform else { return }
        if Prefs.performanceMode == .fakeRingtone, isArmed {
            applyFakePerformMediaVolumeBoost(reason: "notesReady")
        }
        if SharePerformFlow.shared.isActive {
            NotesSongSession.shared.lockForShare()
            SharePerformFlow.shared.songLocked()
        }
    }

    /// API locked a loaded song. Fake Ringtone is already hot via select(); Share opens the Share sheet.
    func apiSongLocked(context: ApiSongSession.Context) {
        if context == .perform, Prefs.performanceMode == .fakeRingtone, isArmed {
            applyFakePerformMediaVolumeBoost(reason: "apiLocked")
        }
        if context == .perform, SharePerformFlow.shared.isActive {
            SharePerformFlow.shared.songLocked()
        }
    }

    /// Leaving Perform starts the next performance from zero (no stale song on the next run).
    func resetVoicePerformance() {
        SharePerformFlow.shared.reset()
        VoiceSongSession.shared.reset(reason: "left Perform")
        NotesSongSession.shared.reset(reason: "left Perform")
        ApiSongSession.shared.reset(reason: "left Perform")
        clearSongForNextPerformance()
    }

    /// Home screen: switching song input must not leave a preview loaded from AI Voice / Notes / API Test.
    func resetAfterSongInputModeChange(from previous: VoiceSettings.InputMode, to next: VoiceSettings.InputMode) {
        guard previous != next else { return }
        VoiceSongSession.shared.reset(reason: "input mode \(previous.title) → \(next.title)")
        NotesSongSession.shared.reset(reason: "input mode")
        ApiSongSession.shared.reset(reason: "input mode")
        if previous != .manual || next != .manual {
            clearSongForNextPerformance()
        }
    }
}
