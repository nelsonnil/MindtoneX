import Foundation
import UIKit

extension AppModel {
    var usesVoiceInput: Bool { VoiceSettings.inputMode == .aiVoice }

    /// Perform button for both modes and both song inputs.
    func perform() {
        let voice = usesVoiceInput
        dlog("══ PERFORM ══ mode=\(Prefs.performanceMode.title) input=\(VoiceSettings.inputMode.title)")
        switch Prefs.performanceMode {
        case .fakeRingtone:
            if voice {
                VoiceSongSession.shared.reset(reason: "new Perform")
                clearSongForNextPerformance()
                VoiceAudioSession.recordCategoryActive = true
                arm(requireSong: false)
                Task { await VoiceSongSession.shared.start(context: .perform) }
            } else {
                performFakeRingtone()
            }
        case .shareRingtone:
            if voice {
                VoiceSongSession.shared.reset(reason: "new Perform")
                clearSongForNextPerformance()
            }
            SharePerformFlow.shared.start(withVoice: voice)
        }
    }

    var canPerform: Bool {
        usesVoiceInput ? VoiceSettings.isConfigured : loadState == .ready
    }

    /// Looks up and loads a voice candidate with the normal preview lookup.
    func prepareVoiceCandidate(_ pick: SongPick) async -> Bool {
        query = pick.searchQuery
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
            SharePerformFlow.shared.voiceLocked()
        }
    }

    /// Leaving Perform starts the next performance from zero.
    func resetVoicePerformance() {
        SharePerformFlow.shared.reset()
        VoiceSongSession.shared.reset(reason: "left Perform")
        if usesVoiceInput { clearSongForNextPerformance() }
    }
}
