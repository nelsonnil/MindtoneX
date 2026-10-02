import Foundation

/// Preferences for the Notes song input. Views use @AppStorage with the same keys.
enum NotesSettings {
    enum Key {
        static let idleSearchEnabled = "notes.idleSearchEnabled"
        static let idleDelay = "notes.idleDelay"
        static let searchOnReturn = "notes.searchOnReturn"
        static let useAIPicker = "notes.useAIPicker"
        static let hapticOnReady = "notes.hapticOnReady"
    }

    static let defaultIdleDelay = 3.0
    static let idleDelayRange: ClosedRange<Double> = 1...15

    private static var d: UserDefaults { .standard }

    static var idleSearchEnabled: Bool { bool(Key.idleSearchEnabled, default: true) }
    static var idleDelay: Double {
        guard d.object(forKey: Key.idleDelay) != nil else { return defaultIdleDelay }
        return min(max(d.double(forKey: Key.idleDelay), idleDelayRange.lowerBound), idleDelayRange.upperBound)
    }
    static var searchOnReturn: Bool { bool(Key.searchOnReturn, default: true) }
    /// With an OpenAI key, the AI reads the note and returns a clean “title artist” query.
    static var useAIPicker: Bool { bool(Key.useAIPicker, default: true) }
    static var hapticOnReady: Bool { bool(Key.hapticOnReady, default: false) }

    static var aiAvailable: Bool { useAIPicker && VoiceSettings.apiKey != nil }

    static func summary() -> String {
        "idle=\(idleSearchEnabled ? "\(idleDelay)s" : "off") return=\(searchOnReturn) ai=\(aiAvailable) haptic=\(hapticOnReady)"
    }

    private static func bool(_ key: String, default value: Bool) -> Bool {
        d.object(forKey: key) == nil ? value : d.bool(forKey: key)
    }
}
