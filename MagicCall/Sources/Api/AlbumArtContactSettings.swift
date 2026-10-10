import Foundation

/// Album artwork on the spectator contact during Perform (incoming call photo).
enum AlbumArtContactSettings {
    enum Key {
        static let enabled = "albumArtContact.enabled"
    }

    private static var d: UserDefaults { .standard }

    static var enabled: Bool {
        d.bool(forKey: Key.enabled)
    }

    static func setEnabled(_ on: Bool) {
        d.set(on, forKey: Key.enabled)
    }
}
