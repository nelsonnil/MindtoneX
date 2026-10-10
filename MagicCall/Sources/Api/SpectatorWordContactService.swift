import Contacts
import Foundation

/// Creates or renames Contacts for the Word API spectator phone (no Contacts UI during save).
enum SpectatorWordContactService {
    private static let store = CNContactStore()
    @MainActor
    static func applyOnWordLock(word: String, reason: String) {
        guard WordApiSettings.saveWordAsContactEnabled else {
            dlogDebug("[CONTACT] skip (\(reason)): save-word-as-contact off")
            return
        }
        let label = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return }

        switch WordApiSettings.contactMode {
        case .unknown:
            guard let phone = WordApiSettings.identificationPhoneE164String() else {
                dlog("[CONTACT] skip (\(reason)): no phone (Unknown — dial before Perform)")
                PerformUserLog.shared.log("Contact not saved · dial spectator number before Perform (Unknown mode)")
                return
            }
            Task { await applyWordToContactsByPhone(word: label, phone: phone, reason: reason) }
        case .known:
            guard let id = WordApiSettings.knownContactIdentifier else {
                dlog("[CONTACT] skip (\(reason)): no known contact picked")
                PerformUserLog.shared.log("Contact not renamed · choose a contact on Caller name (Known mode)")
                return
            }
            Task { await applyWordToKnownContact(identifier: id, word: label, reason: reason) }
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
        WordApiSettings.setKnownContactRenamedForShow(false)
        dlogDebug("[CONTACT] picked «\(label)» · \(phoneE164) · id=\(WordApiInputPanel.truncated(contact.identifier, max: 16))")
    }

    /// Reverts Contacts changed at word lock (Perform disarm / settings dismiss).
    @MainActor
    static func restoreContactsAfterPerform(reason: String) {
        let snapshots = WordApiContactRestoreStore.entries
        guard !snapshots.isEmpty else { return }

        guard WordApiSettings.saveWordAsContactEnabled, WordApiSettings.restoreKnownNameOnSettingsExit else {
            WordApiContactRestoreStore.clear()
            WordApiSettings.setKnownContactRenamedForShow(false)
            return
        }

        Task {
            await runRestoreSnapshots(snapshots, reason: reason)
        }
    }

    // MARK: - Private

    @MainActor
    private static func applyWordToKnownContact(identifier: String, word: String, reason: String) async {
        guard await ensureContactsAccess(reason: reason) else { return }
        do {
            let outcome = try renameKnownContactGivenName(identifier: identifier, word: word)
            WordApiSettings.setKnownContactRenamedForShow(WordApiContactRestoreStore.hasPendingRestore)
            dlogDebug("[CONTACT] renamed known → «\(word)» (\(reason)) · \(outcome.debugSummary)")
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
    private static func applyWordToContactsByPhone(word: String, phone: String, reason: String) async {
        guard await ensureContactsAccess(reason: reason) else { return }
        do {
            let outcome = try upsertByPhone(word: word, phone: phone)
            WordApiSettings.setKnownContactRenamedForShow(WordApiContactRestoreStore.hasPendingRestore)
            dlogDebug("[CONTACT] saved «\(word)» → \(phone) (\(reason)) · \(outcome.debugSummary)")
            PerformUserLog.shared.log("Contact saved · \(phone) · incoming call will show “\(WordApiInputPanel.truncated(outcome.displayName, max: 40))”\(outcome.warnings)")
        } catch {
            dlog("✗ [CONTACT] save (\(reason)): \(error.localizedDescription)")
            PerformUserLog.shared.log("Contact not saved · \(describe(error))")
            return
        }
        let note = performContactNote()
        if !note.isEmpty {
            await updateNoteForPhone(phone: phone, note: note, reason: reason)
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
        SpectatorContactFetch.userFacingMessage(for: error)
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
    private static func runRestoreSnapshots(_ snapshots: [WordApiContactRestoreEntry], reason: String) async {
        guard await ensureContactsAccess(reason: reason) else { return }
        var restored = 0
        var deleted = 0
        for entry in snapshots {
            do {
                if entry.createdForShow {
                    try deleteContact(identifier: entry.identifier)
                    deleted += 1
                } else {
                    try setGivenName(identifier: entry.identifier, givenName: entry.givenName)
                    restored += 1
                }
            } catch {
                dlog("✗ [CONTACT] restore \(entry.identifier) (\(reason)): \(error.localizedDescription)")
            }
        }
        WordApiContactRestoreStore.clear()
        WordApiSettings.setKnownContactRenamedForShow(false)
        if restored + deleted > 0 {
            dlog("[CONTACT] restore (\(reason)) · \(restored) renamed · \(deleted) deleted")
            PerformUserLog.shared.log("Contacts restored after Perform · \(restored + deleted) card(s)")
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

    private static func upsertByPhone(word: String, phone: String) throws -> SaveOutcome {
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
        ] + displayKeys
        let matches = try cards(withPhone: phone, keysToFetch: keys)
        let save = CNSaveRequest()
        var saved: [CNMutableContact] = []
        var restoreEntries: [WordApiContactRestoreEntry] = []

        if matches.isEmpty {
            let contact = CNMutableContact()
            contact.givenName = word
            contact.phoneNumbers = [
                CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: phone)),
            ]
            save.add(contact, toContainerWithIdentifier: store.defaultContainerIdentifier())
            try store.execute(save)
            restoreEntries = [
                WordApiContactRestoreEntry(
                    identifier: contact.identifier,
                    givenName: "",
                    createdForShow: true
                ),
            ]
            saved = [contact]
        } else {
            restoreEntries = matches.map {
                WordApiContactRestoreEntry(
                    identifier: $0.identifier,
                    givenName: $0.givenName,
                    createdForShow: false
                )
            }
            for existing in matches {
                let mutable = existing.mutableCopy() as! CNMutableContact
                mutable.givenName = word
                save.update(mutable)
                saved.append(mutable)
            }
            try store.execute(save)
        }
        WordApiContactRestoreStore.replaceEntries(restoreEntries)
        return outcome(for: saved[0], cardsRenamed: saved.count, otherCardsWithNumber: 0, fallback: word)
    }

    private static func renameKnownContactGivenName(identifier: String, word: String) throws -> SaveOutcome {
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
        ] + displayKeys
        let resolution = try SpectatorContactFetch.resolveKnownContact(store: store, keysToFetch: keys)
        let contact = resolution.contact
        if resolution.resolvedByPhone {
            dlog("[CONTACT] known re-resolved by phone · \(resolution.phoneMatchCount) match(es) · id=\(WordApiInputPanel.truncated(contact.identifier, max: 16))")
        }
        WordApiContactRestoreStore.replaceEntries([
            WordApiContactRestoreEntry(
                identifier: contact.identifier,
                givenName: contact.givenName,
                createdForShow: false
            ),
        ])
        let mutable = contact.mutableCopy() as! CNMutableContact
        mutable.givenName = word
        let save = CNSaveRequest()
        save.update(mutable)
        try store.execute(save)
        var others = 0
        if let phone = WordApiSettings.identificationPhoneE164String() {
            let sharing = (try? cards(withPhone: phone, keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor])) ?? []
            others = sharing.filter { $0.identifier != contact.identifier }.count
        }
        return outcome(for: mutable, cardsRenamed: 1, otherCardsWithNumber: others, fallback: word)
    }

    private static func deleteContact(identifier: String) throws {
        let keys: [CNKeyDescriptor] = [CNContactIdentifierKey as CNKeyDescriptor]
        let contact = try SpectatorContactFetch.unifiedContact(
            store: store,
            identifier: identifier,
            keysToFetch: keys
        )
        let mutable = contact.mutableCopy() as! CNMutableContact
        let save = CNSaveRequest()
        save.delete(mutable)
        try store.execute(save)
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
        guard WordApiSettings.notesContactTargetsCard else { return }
        let note = NotesContactSettings.resolvedContactNote(
            lockedWord: NotesContactWordSession.shared.lockedReading?.label
        )
        guard !note.isEmpty || !NotesContactSettings.storedNoteBody.isEmpty else { return }

        switch WordApiSettings.contactMode {
        case .unknown:
            guard let phone = WordApiSettings.spectatorContactPhoneE164String() else { return }
            Task { await updateNoteForPhone(phone: phone, note: note, reason: reason) }
        case .known:
            guard let id = WordApiSettings.knownContactIdentifier else { return }
            Task { await updateNoteForKnown(identifier: id, note: note, reason: reason) }
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
            let contact = try SpectatorContactFetch.resolveKnownContact(store: store, keysToFetch: keys).contact
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

    private static func setGivenName(identifier: String, givenName: String) throws {
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
        ]
        let contact = try SpectatorContactFetch.unifiedContact(
            store: store,
            identifier: identifier,
            keysToFetch: keys
        )
        let mutable = contact.mutableCopy() as! CNMutableContact
        mutable.givenName = givenName
        let save = CNSaveRequest()
        save.update(mutable)
        try store.execute(save)
    }
}
