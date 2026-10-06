import Foundation

/// Which spectator answers the mic must decode during Perform (one shared transcript when Song = Voice).
enum SpectatorListenChannel: String, CaseIterable, Identifiable {
    case song
    case callerName
    case notesContact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .song: return "Song"
        case .callerName: return "Caller name"
        case .notesContact: return "Notes contact"
        }
    }

    /// Short script hint for the magician (English — same as rest of performer UI).
    var magicianScriptHint: String {
        switch self {
        case .song:
            return "Ask for any song title — spectator names the track they want."
        case .callerName:
            return "Ask: “What word do you think I saved as your contact on your phone?” — they answer with one word."
        case .notesContact:
            return "Ask: “What word do you think appears on the contact button in my note?” — one word answer."
        }
    }
}

/// Active AI listeners for the current home setup — avoids one prompt trying to guess song + both words at once.
struct VoiceListenPlan: Equatable {
    var song: Bool
    var callerName: Bool
    var notesContact: Bool

    var activeChannels: [SpectatorListenChannel] {
        SpectatorListenChannel.allCases.filter { includes($0) }
    }

    func includes(_ channel: SpectatorListenChannel) -> Bool {
        switch channel {
        case .song: return song
        case .callerName: return callerName
        case .notesContact: return notesContact
        }
    }

    /// Voice word channels share the Song-input microphone (Perform must use Song input = Voice).
    var requiresSongVoiceMic: Bool { callerName || notesContact }

    static var current: VoiceListenPlan {
        let songVoice = VoiceSettings.inputMode == .aiVoice && VoiceSettings.isConfigured
        let sharedMicOK = songVoice
        let caller = WordApiSettings.callerLabelEnabled
            && WordApiSettings.provider == .voice
            && sharedMicOK
        let notes = NotesContactWordSettings.wordInputEnabled
            && NotesContactWordSettings.provider == .voice
            && sharedMicOK
        return VoiceListenPlan(song: songVoice, callerName: caller, notesContact: notes)
    }
}
