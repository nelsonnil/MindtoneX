import Contacts
import Foundation

/// Creates or renames Contacts for the Word API spectator phone (no Contacts UI during save).
enum SpectatorWordContactService {
    private static let store = CNContactStore()
    @MainActor
    static func applyOnWordLock(word: String, reason: String) {
        guard WordApiSettings.saveWordAsContactEnabled else {
            dlog("[CONTACT] skip (\(reason)): save-word-as-contact off")
            return
        }
        let label = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return }

        switch WordApiSettings.contactMode {
        case .unknown:
            guard let phone = WordApiSettings.identificationPhoneE164String() else {
                dlog("[CONTACT] skip (\(reason)): no phone (unknown mode — dial before Perform)")
                PerformUserLog.shared.log("Contact not saved · dial spectator number before Perform (Unknown mode)")
                return
            }
            Task { await createUnknownIfNeeded(word: label, phone: phone, reason: reason) }
        case .known:
            guard let id = WordApiSettings.knownContactIdentifier else {
                dlog("[CONTACT] skip (\(reason)): no known contact picked")
                PerformUserLog.shared.log("Contact not renamed · choose a contact on the Word API card (Known mode)")
                return
            }
            Task { await renameKnownContact(identifier: id, word: label, reason: reason) }
        }
    }

    /// Restores the known contact’s original given name (Settings exit / manual cleanup).
    @MainActor
    static func restoreKnownContactOriginalName(reason: String) {
        guard WordApiSettings.saveWordAsContactEnabled else { return }
        guard WordApiSettings.contactMode == .known else { return }
        guard WordApiSettings.restoreKnownNameOnSettingsExit else { return }
        guard WordApiContactShowState.shared.knownContactRenamedForShow else { return }
        guard let id = WordApiSettings.knownContactIdentifier else { return }
        let original = WordApiSettings.knownContactOriginalGivenName
        guard !original.isEmpty else { return }

        Task {
            await runRestore(identifier: id, givenName: original, reason: reason)
        }
    }

    @MainActor
    static func recordKnownContactPicked(_ contact: CNContact, phoneE164: String) {
        let digits = WordApiSettings.normalizePhoneDigits(phoneE164)
        let display = [contact.givenName, contact.familyName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let label = display.isEmpty ? phoneE164 : display
        WordApiSettings.saveKnownContactSelection(
            identifier: contact.identifier,
            displayName: label,
            phoneDigits: digits,
            originalGivenName: contact.givenName
        )
        WordApiContactShowState.shared.knownContactRenamedForShow = false
        dlog("[CONTACT] picked «\(label)» · \(phoneE164)")
    }

    // MARK: - Private

    @MainActor
    private static func createUnknownIfNeeded(word: String, phone: String, reason: String) async {
        guard await ensureContactsAccess(reason: reason) else { return }
        do {
            let note = NotesContactSettings.resolvedContactNote(
                lockedWord: NotesContactWordSession.shared.lockedReading?.label
            )
            try upsertUnknown(word: word, phone: phone, note: note)
            dlog("[CONTACT] created/updated unknown «\(word)» → \(phone) (\(reason))")
            PerformUserLog.shared.log("Contact saved · incoming call will show “\(WordApiInputPanel.truncated(word, max: 32))”")
        } catch {
            dlog("✗ [CONTACT] unknown (\(reason)): \(error.localizedDescription)")
            PerformUserLog.shared.log("Contact not saved · \(error.localizedDescription)")
        }
    }

    @MainActor
    private static func renameKnownContact(identifier: String, word: String, reason: String) async {
        guard await ensureContactsAccess(reason: reason) else { return }
        do {
            let note = NotesContactSettings.resolvedContactNote(
                lockedWord: NotesContactWordSession.shared.lockedReading?.label
            )
            try renameGivenName(identifier: identifier, word: word, note: note)
            WordApiContactShowState.shared.knownContactRenamedForShow = true
            dlog("[CONTACT] renamed known → «\(word)» (\(reason))")
            PerformUserLog.shared.log("Contact renamed · incoming call will show “\(WordApiInputPanel.truncated(word, max: 32))”")
        } catch {
            dlog("✗ [CONTACT] known rename (\(reason)): \(error.localizedDescription)")
            PerformUserLog.shared.log("Contact not renamed · \(error.localizedDescription)")
        }
    }

    @MainActor
    private static func runRestore(identifier: String, givenName: String, reason: String) async {
        guard await ensureContactsAccess(reason: reason) else { return }
        do {
            try setGivenName(identifier: identifier, givenName: givenName)
            WordApiContactShowState.shared.knownContactRenamedForShow = false
            dlog("[CONTACT] restored givenName «\(givenName)» (\(reason))")
            PerformUserLog.shared.log("Contact name restored · «\(WordApiInputPanel.truncated(givenName, max: 32))»")
        } catch {
            dlog("✗ [CONTACT] restore (\(reason)): \(error.localizedDescription)")
        }
    }

    @MainActor
    private static func ensureContactsAccess(reason: String) async -> Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let granted = await requestAccess()
            if !granted { logDenied(reason: reason) }
            return granted
        case .denied, .restricted:
            logDenied(reason: reason)
            return false
        @unknown default:
            logDenied(reason: reason)
            return false
        }
    }

    private static func requestAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            store.requestAccess(for: .contacts) { granted, error in
                if let error {
                    dlog("✗ [CONTACT] permission: \(error.localizedDescription)")
                }
                continuation.resume(returning: granted)
            }
        }
    }

    @MainActor
    private static func logDenied(reason: String) {
        dlog("[CONTACT] denied (\(reason)) — Call Directory label only")
        PerformUserLog.shared.logConnectionIssue(
            "Contacts access off · enable in Settings for the word as caller name, or rely on Call Directory."
        )
    }

    private static func upsertUnknown(word: String, phone: String, note: String) throws {
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactNoteKey as CNKeyDescriptor,
        ]
        let number = CNPhoneNumber(stringValue: phone)
        let matches = try store.unifiedContacts(
            matching: CNContact.predicateForContacts(matching: number),
            keysToFetch: keys
        )
        let save = CNSaveRequest()

        if let existing = matches.first {
            let mutable = existing.mutableCopy() as! CNMutableContact
            mutable.givenName = word
            mutable.note = note
            ensurePhone(mutable, phone: phone, number: number)
            save.update(mutable)
        } else {
            let contact = CNMutableContact()
            contact.givenName = word
            contact.note = note
            contact.phoneNumbers = [
                CNLabeledValue(label: CNLabelPhoneNumberMobile, value: number),
            ]
            save.add(contact, toContainerWithIdentifier: store.defaultContainerIdentifier())
        }
        try store.execute(save)
    }

    private static func renameGivenName(identifier: String, word: String, note: String) throws {
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactNoteKey as CNKeyDescriptor,
        ]
        let contact = try store.unifiedContact(withIdentifier: identifier, keysToFetch: keys)
        WordApiSettings.saveKnownContactGivenNameBeforeLock(contact.givenName)
        let mutable = contact.mutableCopy() as! CNMutableContact
        mutable.givenName = word
        mutable.note = note
        let save = CNSaveRequest()
        save.update(mutable)
        try store.execute(save)
    }

    /// Refresh Contacts **Notes** when the Notes chip word locks (template + placeholder).
    @MainActor
    static func applyContactNoteFromSettings(reason: String) {
        guard WordApiSettings.saveWordAsContactEnabled else { return }
        let note = NotesContactSettings.resolvedContactNote(
            lockedWord: NotesContactWordSession.shared.lockedReading?.label
        )
        guard !note.isEmpty || !NotesContactSettings.storedNoteBody.isEmpty else { return }

        switch WordApiSettings.contactMode {
        case .unknown:
            guard let phone = WordApiSettings.identificationPhoneE164String() else { return }
            Task { await updateNoteForPhone(phone: phone, note: note, reason: reason) }
        case .known:
            guard let id = WordApiSettings.knownContactIdentifier else { return }
            Task { await updateNoteForKnown(identifier: id, note: note, reason: reason) }
        }
    }

    @MainActor
    private static func updateNoteForPhone(phone: String, note: String, reason: String) async {
        guard await ensureContactsAccess(reason: reason) else { return }
        do {
            let keys: [CNKeyDescriptor] = [
                CNContactIdentifierKey as CNKeyDescriptor,
                CNContactNoteKey as CNKeyDescriptor,
                CNContactPhoneNumbersKey as CNKeyDescriptor,
            ]
            let number = CNPhoneNumber(stringValue: phone)
            let matches = try store.unifiedContacts(
                matching: CNContact.predicateForContacts(matching: number),
                keysToFetch: keys
            )
            guard let existing = matches.first else { return }
            let mutable = existing.mutableCopy() as! CNMutableContact
            mutable.note = note
            let save = CNSaveRequest()
            save.update(mutable)
            try store.execute(save)
            dlog("[CONTACT] note updated (\(reason)) · \(note.prefix(40))…")
        } catch {
            dlog("✗ [CONTACT] note (\(reason)): \(error.localizedDescription)")
        }
    }

    @MainActor
    private static func updateNoteForKnown(identifier: String, note: String, reason: String) async {
        guard await ensureContactsAccess(reason: reason) else { return }
        do {
            let keys: [CNKeyDescriptor] = [
                CNContactIdentifierKey as CNKeyDescriptor,
                CNContactNoteKey as CNKeyDescriptor,
            ]
            let contact = try store.unifiedContact(withIdentifier: identifier, keysToFetch: keys)
            let mutable = contact.mutableCopy() as! CNMutableContact
            mutable.note = note
            let save = CNSaveRequest()
            save.update(mutable)
            try store.execute(save)
            dlog("[CONTACT] known note updated (\(reason))")
        } catch {
            dlog("✗ [CONTACT] known note (\(reason)): \(error.localizedDescription)")
        }
    }

    private static func setGivenName(identifier: String, givenName: String) throws {
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
        ]
        let contact = try store.unifiedContact(withIdentifier: identifier, keysToFetch: keys)
        let mutable = contact.mutableCopy() as! CNMutableContact
        mutable.givenName = givenName
        let save = CNSaveRequest()
        save.update(mutable)
        try store.execute(save)
    }

    private static func ensurePhone(_ contact: CNMutableContact, phone: String, number: CNPhoneNumber) {
        let normalized = WordApiSettings.normalizePhoneDigits(phone)
        let hasNumber = contact.phoneNumbers.contains { labeled in
            WordApiSettings.normalizePhoneDigits(labeled.value.stringValue) == normalized
        }
        guard !hasNumber else { return }
        contact.phoneNumbers.append(CNLabeledValue(label: CNLabelPhoneNumberMobile, value: number))
    }
}
