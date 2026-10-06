import Foundation

/// Home **Notes contact** card — note body + chip label filled from Caller name (OCR / API).
enum NotesContactSettings {
    enum Key {
        static let noteBody = "notesContact.bodyText"
        static let buttonPlaceholder = "notesContact.buttonPlaceholder"
    }

    static let defaultButtonPlaceholder = "Contact"

    private static var d: UserDefaults { .standard }

    static func registerDefaults() {
        d.register(defaults: [
            Key.buttonPlaceholder: defaultButtonPlaceholder,
        ])
    }
}
