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
            let outcome = try upsertUnknown(word: word, phone: phone)
            dlog("[CONTACT] created/updated unknown «\(word)» → \(phone) (\(reason)) · \(outcome.debugSummary)")
            PerformUserLog.shared.log("Contact saved · \(phone) · incoming call will show “\(WordApiInputPanel.truncated(outcome.displayName, max: 40))”\(outcome.warnings)")
        } catch {
            dlog("✗ [CONTACT] unknown (\(reason)): \(error.localizedDescription)")
            PerformUserLog.shared.log("Contact not saved · \(describe(error))")
            return
        }
        let note = performContactNote()
        if !note.isEmpty {
            await updateNoteForPhone(phone: phone, note: note, reason: reason)
        }
    }

    @MainActor
    private static func renameKnownContact(identifier: String, word: String, reason: String) async {
        guard await ensureContactsAccess(reason: reason) else { return }
        do {
            let outcome = try renameGivenName(identifier: identifier, word: word)
            WordApiContactShowState.shared.knownContactRenamedForShow = true
            dlog("[CONTACT] renamed known → «\(word)» (\(reason)) · \(outcome.debugSummary)")
            PerformUserLog.shared.log("Contact renamed · incoming call will show “\(WordApiInputPanel.truncated(outcome.displayName, max: 40))”\(outcome.warnings)")
        } catch {
            dlog("✗ [CONTACT] known rename (\(reason)): \(error.localizedDescription)")
            PerformUserLog.shared.log("Contact not renamed · \(describe(error))")
            return
        }
        let note = performContactNote()
        if !note.isEmpty {
            await updateNoteForKnown(identifier: identifier, note: note, reason: reason)
        }
    }

    @MainActor
    private static func performContactNote() -> String {
        NotesContactSettings.resolvedContactNote(
            lockedWord: NotesContactWordSession.shared.lockedReading?.label
        )
    }

    /// `CNContactNoteKey` needs Apple's `com.apple.developer.contacts.notes` entitlement; without it every
    /// fetch that asks for the note fails with `unauthorizedKeys`, so notes stay out of the name save.
    private static func isMissingNotesEntitlement(_ error: Error) -> Bool {
        (error as? CNError)?.code == .unauthorizedKeys
    }

    private static func describe(_ error: Error) -> String {
        guard let cnError = error as? CNError else { return error.localizedDescription }
        return "\(error.localizedDescription) (Contacts error \(cnError.code.rawValue))"
    }

    @MainActor
    private static func logNoteSkipped(_ error: Error, reason: String) {
        guard isMissingNotesEntitlement(error) else {
            dlog("✗ [CONTACT] note (\(reason)): \(error.localizedDescription)")
            return
        }
        dlog("[CONTACT] note skipped (\(reason)): app lacks com.apple.developer.contacts.notes")
        PerformUserLog.shared.logOncePerSession(
            "contact.note-entitlement",
            "Contact note skipped · this build has no Contacts Notes entitlement (caller name still saved)"
        )
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

    /// What iOS will most likely put on the incoming call screen after the save.
    struct SaveOutcome {
        var displayName: String
        var nickname: String
        var cardsRenamed: Int
        /// Cards with the spectator number that keep their own name; iOS may show any of them.
        var otherCardsWithNumber: Int
        var limitedAccess: Bool

        var warnings: String {
            var parts: [String] = []
            if otherCardsWithNumber > 0 {
                parts.append("\(otherCardsWithNumber) other contact(s) have this number — iOS may show one of them")
            }
            if !nickname.isEmpty {
                parts.append("card nickname «\(nickname)» may show instead")
            }
            if limitedAccess {
                parts.append("Contacts access is Limited — a hidden card with this number would win")
            }
            let renamed = cardsRenamed > 1 ? " · \(cardsRenamed) cards with this number renamed" : ""
            return renamed + (parts.isEmpty ? "" : " · ⚠ " + parts.joined(separator: " · "))
        }

        var debugSummary: String {
            "display=«\(displayName)» nickname=«\(nickname)» renamed=\(cardsRenamed) others=\(otherCardsWithNumber) limited=\(limitedAccess)"
        }
    }

    private static var displayKeys: [CNKeyDescriptor] {
        [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactNicknameKey as CNKeyDescriptor,
        ]
    }

    private static var isLimitedAccess: Bool {
        guard #available(iOS 18.0, *) else { return false }
        return CNContactStore.authorizationStatus(for: .contacts) == .limited
    }

    private static func outcome(
        for contact: CNContact,
        cardsRenamed: Int,
        otherCardsWithNumber: Int,
        fallback: String
    ) -> SaveOutcome {
        let formatted = CNContactFormatter.string(from: contact, style: .fullName)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return SaveOutcome(
            displayName: formatted.isEmpty ? fallback : formatted,
            nickname: contact.nickname.trimmingCharacters(in: .whitespacesAndNewlines),
            cardsRenamed: cardsRenamed,
            otherCardsWithNumber: otherCardsWithNumber,
            limitedAccess: isLimitedAccess
        )
    }

    private static func cards(withPhone phone: String, keysToFetch keys: [CNKeyDescriptor]) throws -> [CNContact] {
        try store.unifiedContacts(
            matching: CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: phone)),
            keysToFetch: keys
        )
    }

    private static func upsertUnknown(word: String, phone: String) throws -> SaveOutcome {
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
        ] + displayKeys
        let matches = try cards(withPhone: phone, keysToFetch: keys)
        let save = CNSaveRequest()
        var saved: [CNMutableContact] = []

        if matches.isEmpty {
            let contact = CNMutableContact()
            contact.givenName = word
            contact.phoneNumbers = [
                CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: phone)),
            ]
            save.add(contact, toContainerWithIdentifier: store.defaultContainerIdentifier())
            saved = [contact]
        } else {
            // iOS may show any card that carries the number, so every one of them gets the word.
            for existing in matches {
                let mutable = existing.mutableCopy() as! CNMutableContact
                mutable.givenName = word
                save.update(mutable)
                saved.append(mutable)
            }
        }
        try store.execute(save)
        return outcome(for: saved[0], cardsRenamed: saved.count, otherCardsWithNumber: 0, fallback: word)
    }

    private static func renameGivenName(identifier: String, word: String) throws -> SaveOutcome {
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
        ] + displayKeys
        let contact = try store.unifiedContact(withIdentifier: identifier, keysToFetch: keys)
        WordApiSettings.saveKnownContactGivenNameBeforeLock(contact.givenName)
        let mutable = contact.mutableCopy() as! CNMutableContact
        mutable.givenName = word
        let save = CNSaveRequest()
        save.update(mutable)
        try store.execute(save)
        var others = 0
        if let phone = WordApiSettings.identificationPhoneE164String() {
            let sharing = (try? cards(withPhone: phone, keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor])) ?? []
            others = sharing.filter { $0.identifier != identifier }.count
        }
        return outcome(for: mutable, cardsRenamed: 1, otherCardsWithNumber: others, fallback: word)
    }

    /// Call Directory labels only numbers that are **not** in Contacts; warn when Contacts save is off.
    @MainActor
    static func logContactOverridingCallDirectory(phone: String) {
        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized || isLimitedAccess else {
            PerformUserLog.shared.log(
                "Caller name · Contacts not readable, so MindtoneX can't check \(phone) — if a card has that number (old MindtoneX card too), iOS shows the card, not the word."
            )
            return
        }
        let matches = (try? cards(withPhone: phone, keysToFetch: displayKeys)) ?? []
        guard let first = matches.first else { return }
        let name = outcome(for: first, cardsRenamed: 0, otherCardsWithNumber: matches.count - 1, fallback: phone).displayName
        dlog("[CONTACT] \(phone) already in Contacts as «\(name)» (\(matches.count)) — overrides Call Directory label")
        PerformUserLog.shared.log(
            "Caller name · \(phone) is saved in Contacts as «\(WordApiInputPanel.truncated(name, max: 32))» — iOS shows that name, not the word. Turn Save word as contact ON or delete that contact."
        )
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
            ]
            let matches = try cards(withPhone: phone, keysToFetch: keys)
            guard !matches.isEmpty else { return }
            let save = CNSaveRequest()
            for existing in matches {
                let mutable = existing.mutableCopy() as! CNMutableContact
                mutable.note = note
                save.update(mutable)
            }
            try store.execute(save)
            dlog("[CONTACT] note updated (\(reason)) · \(note.prefix(40))…")
        } catch {
            logNoteSkipped(error, reason: reason)
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
            logNoteSkipped(error, reason: reason)
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
}
