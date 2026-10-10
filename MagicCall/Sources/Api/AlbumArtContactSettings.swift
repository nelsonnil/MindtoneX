import Foundation

/// Album artwork on song lock — contact photo and/or Photo Library save.
enum AlbumArtContactSettings {
    enum Key {
        static let enabled = "albumArtContact.enabled"
        static let saveToPhotos = "albumArtContact.saveToPhotos"
        static let testContactIdentifier = "albumArtContact.testContact.identifier"
        static let testContactDisplayName = "albumArtContact.testContact.displayName"
        static let testContactPhoneDigits = "albumArtContact.testContact.phoneDigits"
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

    static var testContactIdentifier: String? {
        let id = d.string(forKey: Key.testContactIdentifier)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return id.isEmpty ? nil : id
    }

    static var testContactDisplayName: String? {
        let name = d.string(forKey: Key.testContactDisplayName)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? nil : name
    }

    static var testContactPhoneDigits: String {
        d.string(forKey: Key.testContactPhoneDigits)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func saveTestContactSelection(identifier: String, displayName: String, phoneDigits: String) {
        d.set(identifier, forKey: Key.testContactIdentifier)
        d.set(displayName, forKey: Key.testContactDisplayName)
        d.set(WordApiContactPhoneParsing.canonicalDigits(fromContactNumber: phoneDigits), forKey: Key.testContactPhoneDigits)
    }

    static func updateTestContactIdentifier(_ identifier: String) {
        d.set(identifier, forKey: Key.testContactIdentifier)
    }

    static func updateTestContactPhoneDigits(_ phone: String) {
        d.set(WordApiContactPhoneParsing.canonicalDigits(fromContactNumber: phone), forKey: Key.testContactPhoneDigits)
    }

    static func clearTestContactSelection() {
        d.removeObject(forKey: Key.testContactIdentifier)
        d.removeObject(forKey: Key.testContactDisplayName)
        d.removeObject(forKey: Key.testContactPhoneDigits)
    }
}
