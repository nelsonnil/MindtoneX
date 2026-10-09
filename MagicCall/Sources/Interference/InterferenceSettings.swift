import Foundation

/// Interference ringtone (ringtone → hand gesture → radio interference → song).
/// Home › Song › Ringtone. Read by the test lab and by Perform (`AppModel.trigger` → `InterferenceShowController`).
enum InterferenceSettings {
    enum Key {
        static let enabled = "interference.enabled"
        static let ringtoneID = "interference.ringtoneID"
        static let presetID = "interference.presetID"
    }

    enum Ringtone: String, CaseIterable, Identifiable {
        case ringtone1
        case ringtone2

        static let defaultValue = Ringtone.ringtone1

        var id: String { rawValue }

        var title: String {
            switch self {
            case .ringtone1: return "Ringtone 1"
            case .ringtone2: return "Ringtone 2"
            }
        }

        /// File name inside `Resources/InterferenceRingtone/` (folder reference in `project.yml`).
        /// Replace the file with the same name to swap the sound — no Xcode changes needed.
        var resourceName: String {
            switch self {
            case .ringtone1: return "ringtone1-default"
            case .ringtone2: return "ringtone2-optional"
            }
        }
    }

    enum InterferencePreset: String, CaseIterable, Identifiable {
        case radio = "interferencia-radio"
        case slot2 = "interferencia2"
        case slot3 = "interferencia3"
        case slot4 = "interferencia4"

        static let defaultValue = InterferencePreset.radio

        var id: String { rawValue }

        var title: String {
            switch self {
            case .radio: return "Radio"
            case .slot2: return "Interference 2"
            case .slot3: return "Interference 3"
            case .slot4: return "Interference 4"
            }
        }

        /// File name inside `Resources/InterferenceRingtone/` (no extension).
        var resourceName: String { rawValue }
    }

    static let resourceFolder = "InterferenceRingtone"
    static let interferenceResourceName = "interferencia-radio"

    /// Spectators = 2: the second open hand always uses this file (audio of `interferenciaradio2`).
    static let secondHandResourceName = "interferencia-audio2"
    /// After the first confirmed hand, a second hand only counts from this point (anti double trigger).
    static let secondHandCooldown: TimeInterval = 2.0

    static var secondHandInterferenceURL: URL? { bundledAudioURL(named: secondHandResourceName) }

    static var secondHandTitle: String {
        secondHandInterferenceURL != nil ? "Interference audio 2" : "Same as 1st hand (audio 2 file missing)"
    }

    private static var d: UserDefaults { .standard }

    static var enabled: Bool { d.bool(forKey: Key.enabled) }

    static var ringtone: Ringtone {
        Ringtone(rawValue: d.string(forKey: Key.ringtoneID) ?? "") ?? Ringtone.defaultValue
    }

    static var preset: InterferencePreset {
        InterferencePreset(rawValue: d.string(forKey: Key.presetID) ?? "") ?? InterferencePreset.defaultValue
    }

    /// Presets whose `.m4a` is present in the app bundle (missing slots stay hidden in Settings).
    static var bundledPresets: [InterferencePreset] {
        InterferencePreset.allCases.filter { bundledAudioURL(named: $0.resourceName) != nil }
    }

    /// Resolved preset for playback; falls back to default when the saved ID has no bundled file.
    static func resolvedPreset(storedRaw: String?) -> InterferencePreset {
        let stored = InterferencePreset(rawValue: storedRaw ?? "") ?? InterferencePreset.defaultValue
        if bundledAudioURL(named: stored.resourceName) != nil { return stored }
        return bundledPresets.first ?? InterferencePreset.defaultValue
    }

    static func bundledAudioURL(named name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "m4a", subdirectory: resourceFolder)
            ?? Bundle.main.url(forResource: name, withExtension: "m4a")
    }
}
