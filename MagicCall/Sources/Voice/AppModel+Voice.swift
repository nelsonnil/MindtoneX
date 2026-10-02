import Foundation
import UIKit

extension AppModel {
    var usesVoiceInput: Bool { VoiceSettings.inputMode == .aiVoice }
    var usesNotesInput: Bool { VoiceSettings.inputMode == .notes }
    /// AI Voice and Notes find the song during Perform, so each Perform starts with no song.
    var findsSongDuringPerform: Bool { usesVoiceInput || usesNotesInput }

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
        let input = VoiceSettings.inputMode
        dlog("══ PERFORM ══ mode=\(Prefs.performanceMode.title) input=\(input.title)")
        if findsSongDuringPerform {
            VoiceSongSession.shared.reset(reason: "new Perform")
            NotesSongSession.shared.reset(reason: "new Perform")
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

    private func prepareSongQuery(_ text: String) async -> Bool {
        query = text
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
                do { try audio.configureSession() } catch {
                    dlog("✗ [VOICE] back to playback: \(RingtoneAudioEngine.describe(error))")
                }
                if Prefs.hotStandby, audio.player != nil, audio.player?.isPlaying != true { audio.startStandby() }
                dlog("[VOICE] audio back to playback · \(audio.snapshot())")
            } else {
                VoiceAudioSession.deactivateIfIdle()
            }
        }
        if context == .perform, SharePerformFlow.shared.isActive {
            SharePerformFlow.shared.songLocked()
        }
    }

    /// Notes found and loaded a song. Fake Ringtone keeps it hot (select() already restarted
    /// standby); Share Ringtone opens the Share sheet with it.
    func notesSongReady(context: NotesSongSession.Context) {
        guard context == .perform else { return }
        if SharePerformFlow.shared.isActive {
            NotesSongSession.shared.lockForShare()
            SharePerformFlow.shared.songLocked()
        }
    }

    /// Leaving Perform starts the next performance from zero.
    func resetVoicePerformance() {
        SharePerformFlow.shared.reset()
        VoiceSongSession.shared.reset(reason: "left Perform")
        NotesSongSession.shared.reset(reason: "left Perform")
        if findsSongDuringPerform { clearSongForNextPerformance() }
    }
}
