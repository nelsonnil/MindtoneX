import Foundation

/// Home **Notes contact** card — text for the Contacts **Notes** field on the spectator’s card (during / after a call).
enum NotesContactSettings {
    enum Key {
        static let noteBody = "notesContact.bodyText"
        /// Substring in `noteBody` replaced by the locked Notes chip word (API / OCR / Voice). Optional.
        static let buttonPlaceholder = "notesContact.buttonPlaceholder"
    }

    static let defaultButtonPlaceholder = ""

    private static var d: UserDefaults { .standard }

    static func registerDefaults() {
        d.register(defaults: [
            Key.buttonPlaceholder: defaultButtonPlaceholder,
        ])
    }

    static var storedNoteBody: String {
        d.string(forKey: Key.noteBody)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static var storedWordPlaceholder: String {
        d.string(forKey: Key.buttonPlaceholder)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Text written to `CNContact.note`. Empty template → empty note (no app boilerplate).
    static func resolvedContactNote(lockedWord: String?) -> String {
        let template = storedNoteBody
        guard !template.isEmpty else { return "" }
        let token = storedWordPlaceholder
        guard !token.isEmpty, template.contains(token) else { return template }
        let replacement = lockedWord?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? token
        return template.replacingOccurrences(of: token, with: replacement)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
