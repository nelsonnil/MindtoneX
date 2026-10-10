import Foundation

/// Album artwork on song lock — contact photo and/or Photo Library save.
enum AlbumArtContactSettings {
    enum Key {
        static let enabled = "albumArtContact.enabled"
        static let saveToPhotos = "albumArtContact.saveToPhotos"
    }

    private static var d: UserDefaults { .standard }

    static var enabled: Bool {
        d.bool(forKey: Key.enabled)
    }

    static func setEnabled(_ on: Bool) {
        d.set(on, forKey: Key.enabled)
    }

    static var saveToPhotosEnabled: Bool {
        if d.object(forKey: Key.saveToPhotos) != nil {
            return d.bool(forKey: Key.saveToPhotos)
        }
        let legacy = "albumArtPhotos.enabled"
        if d.object(forKey: legacy) != nil {
            let on = d.bool(forKey: legacy)
            d.set(on, forKey: Key.saveToPhotos)
            d.removeObject(forKey: legacy)
            return on
        }
        return false
    }

    static func setSaveToPhotosEnabled(_ on: Bool) {
        d.set(on, forKey: Key.saveToPhotos)
    }

    static var anyOutputEnabled: Bool {
        enabled || saveToPhotosEnabled
    }
}
