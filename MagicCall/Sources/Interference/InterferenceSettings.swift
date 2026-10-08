import Foundation

/// Interference ringtone (ringtone → hand gesture → radio interference → song).
/// Build 1 only drives the Settings test lab; Perform / real calls do not read these keys yet.
enum InterferenceSettings {
    enum Key {
        static let enabled = "interference.enabled"
        static let ringtoneID = "interference.ringtoneID"
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

    static let resourceFolder = "InterferenceRingtone"
    static let interferenceResourceName = "interferencia-radio"

    private static var d: UserDefaults { .standard }

    static var enabled: Bool { d.bool(forKey: Key.enabled) }

    static var ringtone: Ringtone {
        Ringtone(rawValue: d.string(forKey: Key.ringtoneID) ?? "") ?? Ringtone.defaultValue
    }

    static func bundledAudioURL(named name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "m4a", subdirectory: resourceFolder)
            ?? Bundle.main.url(forResource: name, withExtension: "m4a")
    }
}
