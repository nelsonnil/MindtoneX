import Contacts
import ContactsUI
import SwiftUI

struct WordApiSpectatorDialSheet: View {
    @EnvironmentObject private var model: AppModel
    /// Always start blank — spectator dials fresh each Perform (saved only after outgoing call ends).
    @State private var phoneDraft = ""
    @State private var dialAppearanceToken = 0

    private var dialSheetBackground: Color {
        CarphoneDialSystemAppearance.userInterfaceStyle == .dark ? Color.black : Color(uiColor: .systemBackground)
    }

    var body: some View {
        ZStack {
            dialSheetBackground.ignoresSafeArea()
            WordApiCarphoneDialHost(
                phoneDigits: $phoneDraft,
                onCall: startCall,
                onTwoFingerSwipeDown: cancelDialWithoutCall
            )
            .ignoresSafeArea()
        }
        /// Phone dial follows **device** light/dark, not MindtoneX home chrome (`.preferredColorScheme(.dark)`).
        .preferredColorScheme(CarphoneDialSystemAppearance.preferredColorScheme)
        .id(dialAppearanceToken)
        .onAppear { CarphoneDialSystemAppearance.startObservingSystemStyle() }
        .onReceive(NotificationCenter.default.publisher(for: .carphoneDialSystemStyleDidChange)) { _ in
            dialAppearanceToken += 1
        }
        .interactiveDismissDisabled(WordApiContactPerformGate.awaitingOutgoingEnd)
    }

    private func startCall() {
        let digits = WordApiSettings.canonicalPhoneDigits(phoneDraft)
        guard digits.count >= 7 else { return }
        WordApiContactPerformGate.beginDialCapture(phoneDigits: digits)
        guard let url = WordApiSettings.phoneDialURL(storedDigits: digits) else { return }
        model.wordSpectatorDialSheet = false
        model.showStageShellForOutgoingSpectatorCall()
        UIApplication.shared.open(url)
    }

    private func cancelDialWithoutCall() {
        guard !WordApiContactPerformGate.awaitingOutgoingEnd else { return }
        WordApiContactPerformGate.cancelPendingPerform()
        model.wordSpectatorDialSheet = false
    }
}

/// Picker result after unified-store resolution; `phoneE164` is set whenever the card has a usable number.
struct WordApiPickedContact {
    let contact: CNContact
    let phoneE164: String?
    let displayName: String
    /// The pick was a Siri/Recents suggestion with no saved card, so MindtoneX added one.
    var createdFromRecents = false
}

struct WordApiKnownContactPicker: UIViewControllerRepresentable {
    var onPick: (WordApiPickedContact) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick, onCancel: onCancel) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: (WordApiPickedContact) -> Void
        let onCancel: () -> Void

        init(onPick: @escaping (WordApiPickedContact) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let pickerPhone = WordApiContactPhoneParsing.e164(from: contact)
            let pickerName = SpectatorContactFetch.displayName(of: contact)
            let onPick = self.onPick
            SpectatorContactFetch.workQueue.async {
                let picked = Self.resolvePick(contact, pickerPhone: pickerPhone, pickerName: pickerName)
                DispatchQueue.main.async { onPick(picked) }
            }
        }

        private static func resolvePick(_ contact: CNContact, pickerPhone: String?, pickerName: String) -> WordApiPickedContact {
            let idSnippet = WordApiInputPanel.truncated(contact.identifier, max: 16)
            let seed = SpectatorContactFetch.RecentsCardSeed(
                givenName: contact.isKeyAvailable(CNContactGivenNameKey) ? contact.givenName : "",
                familyName: contact.isKeyAvailable(CNContactFamilyNameKey) ? contact.familyName : ""
            )
            do {
                let resolved = try SpectatorContactFetch.resolveContact(
                    store: SpectatorContactFetch.sharedStore,
                    identifier: contact.identifier,
                    phoneDigits: pickerPhone,
                    displayName: pickerName,
                    keysToFetch: [],
                    createFromRecents: seed,
                    log: { contactLog("picker · \($0)") }
                )
                let unified = resolved.contact
                if unified.identifier != contact.identifier {
                    contactLog("picker · id \(idSnippet) → unified \(WordApiInputPanel.truncated(unified.identifier, max: 16))")
                }
                let phone = pickerPhone ?? WordApiContactPhoneParsing.e164(from: unified)
                let name = SpectatorContactFetch.displayName(of: unified)
                let label = name.isEmpty ? pickerName : name
                if resolved.createdFromRecents {
                    contactLog("picker · created real card from Recents · «\(label)» · +\(resolved.matchedPhoneDigits)")
                }
                contactLog("picker · «\(label)» · phone=\(phone ?? "none")")
                return WordApiPickedContact(
                    contact: unified,
                    phoneE164: phone,
                    displayName: label,
                    createdFromRecents: resolved.createdFromRecents
                )
            } catch {
                contactLog("picker · unified lookup failed · id=\(idSnippet) · \(SpectatorContactFetch.errorLogLabel(error)) · phone=\(pickerPhone ?? "none")")
                return WordApiPickedContact(contact: contact, phoneE164: pickerPhone, displayName: pickerName)
            }
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            onCancel()
        }
    }
}

enum WordApiContactPhoneParsing {
    private static let preferredLabels: [String] = [CNLabelPhoneNumberMobile, CNLabelPhoneNumberiPhone, CNLabelPhoneNumberMain]

    /// First usable number on the card (mobile / iPhone / main preferred), as `+<canonical digits>`.
    static func e164(from contact: CNContact) -> String? {
        guard contact.isKeyAvailable(CNContactPhoneNumbersKey) else { return nil }
        let ranked = contact.phoneNumbers.sorted { lhs, rhs in
            rank(lhs.label) < rank(rhs.label)
        }
        for labeled in ranked {
            let digits = canonicalDigits(fromContactNumber: labeled.value.stringValue)
            if digits.count >= 7 { return "+\(digits)" }
        }
        return nil
    }

    private static func rank(_ label: String?) -> Int {
        guard let label, let index = preferredLabels.firstIndex(of: label) else { return preferredLabels.count }
        return index
    }

    /// National card numbers use Settings → Region, then the SIM country when Region would leave them without a country code
    /// (e.g. Region US + Spanish SIM: «629 81 53 39» → 34629815339).
    static func canonicalDigits(fromContactNumber raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = WordApiSettings.normalizePhoneDigits(trimmed)
        if trimmed.hasPrefix("+") || trimmed.hasPrefix("00") { return digits }
        let primary = WordApiSettings.canonicalPhoneDigits(trimmed)
        if primary != digits { return primary }
        let simRegion = WordApiSettings.dialDisplayRegionISO
        guard simRegion != WordApiSettings.deviceRegionISO else { return primary }
        return WordApiSettings.canonicalPhoneDigits(trimmed, region: simRegion)
    }

    /// Same number when canonical forms agree, or the last 9 digits agree (national vs international spellings).
    static func number(_ raw: String, matchesCanonical target: String) -> Bool {
        if canonicalDigits(fromContactNumber: raw) == target { return true }
        let digits = WordApiSettings.normalizePhoneDigits(raw)
        guard digits.count >= 9, target.count >= 9 else { return false }
        return digits.suffix(9) == target.suffix(9)
    }
}

// MARK: - Fetch / user-facing Contacts errors

enum SpectatorContactFetch {
    static let notAccessibleMessage =
        "Contact not accessible — re-pick in Known mode or grant full Contacts access."
    static let transientIdentifierMessage =
        "Saved contact link is temporary (Recents) and has no phone — re-pick the contact in Known mode."

    enum Error: Swift.Error {
        case notAccessible
        case transientIdentifier
    }

    /// Contacts fetch / `CNSaveRequest` must stay off the main thread (iOS warns and can stall UI).
    static let workQueue = DispatchQueue(label: "mindtonex.contacts", qos: .userInitiated)
    static let sharedStore = CNContactStore()

    static func run<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            workQueue.async {
                continuation.resume(with: Result { try work() })
            }
        }
    }

    struct Resolution {
        let contact: CNContact
        let resolvedByPhone: Bool
        let phoneMatchCount: Int
        /// Canonical digits that produced the match (empty when resolved by id or name); the created card's number when `createdFromRecents`.
        let matchedPhoneDigits: String
        let resolvedByName: Bool
        /// No unified card existed for a `CNCoreRecents…` pick, so a real card was added with the picker name + phone.
        var createdFromRecents = false
    }

    /// Optional seed for `resolveContact(createFromRecents:)`; names fall back to `displayName` when empty.
    struct RecentsCardSeed {
        var givenName = ""
        var familyName = ""
        /// Written in the same add request so the new card never exists without its photo.
        var imageData: Data?
    }

    enum RecentsNotice {
        static let identifierKey = "contacts.recentsCreated.identifier"
        static let nameKey = "contacts.recentsCreated.name"

        static func message(name: String) -> String {
            "Created a contact card for «\(name)» (it was only a Recents suggestion)."
        }

        /// Message for the card currently linked as `identifier`, if MindtoneX created it from a Recents pick.
        static func message(forIdentifier identifier: String?) -> String? {
            let d = UserDefaults.standard
            guard let identifier, !identifier.isEmpty,
                  d.string(forKey: identifierKey) == identifier,
                  let name = d.string(forKey: nameKey), !name.isEmpty
            else { return nil }
            return message(name: name)
        }

        fileprivate static func record(identifier: String, name: String) {
            DispatchQueue.main.async {
                UserDefaults.standard.set(identifier, forKey: identifierKey)
                UserDefaults.standard.set(name, forKey: nameKey)
            }
        }
    }

    /// Case-, accent- and width-insensitive, trimmed, single-spaced (`papa` == `Papá` == ` PAPA `).
    static func normalizedName(_ raw: String) -> String {
        raw.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    static func namesMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalizedName(lhs)
        return !left.isEmpty && left == normalizedName(rhs)
    }

    /// Picker / Siri-suggestion ids (`CNCoreRecentsCoordinator…`) are not unified-store records and fail `CNSaveRequest.update`.
    static func isTransientIdentifier(_ identifier: String) -> Bool {
        identifier.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("CNCoreRecents")
    }

    static func displayName(of contact: CNContact) -> String {
        let given = contact.isKeyAvailable(CNContactGivenNameKey) ? contact.givenName : ""
        let family = contact.isKeyAvailable(CNContactFamilyNameKey) ? contact.familyName : ""
        return [given, family]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static var isFullAccess: Bool {
        CNContactStore.authorizationStatus(for: .contacts) == .authorized
    }

    static func errorLogLabel(_ error: Swift.Error) -> String {
        if let cn = error as? CNError {
            return "CNError \(cn.code.rawValue) (\(cn.code)) · \(cn.localizedDescription)"
        }
        if let fetch = error as? Error {
            return "fetch \(fetch)"
        }
        let ns = error as NSError
        return "\(ns.domain) \(ns.code) · \(ns.localizedDescription)"
    }

    private static let matchKeys: [CNKeyDescriptor] = [
        CNContactIdentifierKey as CNKeyDescriptor,
        CNContactGivenNameKey as CNKeyDescriptor,
        CNContactFamilyNameKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor,
    ]

    /// Unified store card for save: durable id first; phone fallback whenever the id is `CNCoreRecents…` or returns no card
    /// (`phoneDigits`, then `fallbackPhoneDigits`); accent/case-insensitive display name last. With `createFromRecents`, a
    /// `CNCoreRecents…` id that matches no card becomes a new real card (name + first phone). Call on `workQueue`.
    static func resolveContact(
        store: CNContactStore,
        identifier: String?,
        phoneDigits: String?,
        displayName: String?,
        fallbackPhoneDigits: [String] = [],
        keysToFetch: [CNKeyDescriptor],
        createFromRecents: RecentsCardSeed? = nil,
        log: ((String) -> Void)? = nil
    ) throws -> Resolution {
        let keys = keysToFetch + matchKeys
        let id = (identifier ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let transient = isTransientIdentifier(id)
        if !id.isEmpty, !transient {
            do {
                let match = try unifiedContact(store: store, identifier: id, keysToFetch: keys)
                return Resolution(contact: match, resolvedByPhone: false, phoneMatchCount: 0, matchedPhoneDigits: "", resolvedByName: false)
            } catch {
                log?("id lookup · 0 cards · \(errorLogLabel(error))")
            }
        } else if transient {
            log?("id is CNCoreRecents (temporary) · phone fallback")
        }

        var phones: [String] = []
        for raw in [phoneDigits ?? ""] + fallbackPhoneDigits {
            let digits = WordApiContactPhoneParsing.canonicalDigits(fromContactNumber: raw)
            if digits.count >= 7, !phones.contains(digits) { phones.append(digits) }
        }
        if phones.isEmpty { log?("phone fallback · no stored phone") }

        for digits in phones {
            let matches = try contacts(withCanonicalDigits: digits, store: store, keysToFetch: keys, log: log)
            log?("phone fallback · +\(digits) · \(matches.count) match(es)")
            guard !matches.isEmpty else { continue }
            let pick = bestMatch(matches, identifier: id, displayName: displayName)
            return Resolution(contact: pick, resolvedByPhone: true, phoneMatchCount: matches.count, matchedPhoneDigits: digits, resolvedByName: false)
        }

        if let byName = try contactByName(displayName, store: store, keysToFetch: keys, log: log) {
            return Resolution(contact: byName, resolvedByPhone: false, phoneMatchCount: 0, matchedPhoneDigits: "", resolvedByName: true)
        }
        if transient, let seed = createFromRecents, let digits = phones.first {
            let created = try createCardFromRecents(
                store: store,
                seed: seed,
                displayName: displayName ?? "",
                phoneDigits: digits,
                keysToFetch: keys,
                log: log
            )
            return Resolution(
                contact: created,
                resolvedByPhone: false,
                phoneMatchCount: 0,
                matchedPhoneDigits: digits,
                resolvedByName: false,
                createdFromRecents: true
            )
        }
        throw (transient && phones.isEmpty) ? Error.transientIdentifier : Error.notAccessible
    }

    /// Known-mode card from saved settings; persists the unified id (and phone when missing) when re-resolved or created
    /// from a Recents pick. Call on `workQueue`.
    static func resolveKnownContact(
        store: CNContactStore,
        keysToFetch: [CNKeyDescriptor],
        log: ((String) -> Void)? = nil
    ) throws -> Resolution {
        let stored = WordApiSettings.knownContactIdentifier
        let resolution = try resolveContact(
            store: store,
            identifier: stored,
            phoneDigits: WordApiSettings.knownContactPhoneDigits,
            displayName: WordApiSettings.knownContactDisplayName,
            keysToFetch: keysToFetch,
            createFromRecents: RecentsCardSeed(givenName: WordApiSettings.knownContactOriginalGivenName),
            log: log
        )
        if resolution.contact.identifier != stored {
            WordApiSettings.updateKnownContactIdentifier(resolution.contact.identifier)
            if WordApiSettings.knownContactPhoneDigits.count < 7,
               let phone = WordApiContactPhoneParsing.e164(from: resolution.contact) {
                WordApiSettings.updateKnownContactPhoneDigits(phone)
            }
        }
        return resolution
    }

    private static func createCardFromRecents(
        store: CNContactStore,
        seed: RecentsCardSeed,
        displayName: String,
        phoneDigits: String,
        keysToFetch keys: [CNKeyDescriptor],
        log: ((String) -> Void)?
    ) throws -> CNContact {
        let card = CNMutableContact()
        let given = seed.givenName.trimmingCharacters(in: .whitespacesAndNewlines)
        let family = seed.familyName.trimmingCharacters(in: .whitespacesAndNewlines)
        if given.isEmpty && family.isEmpty {
            let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            card.givenName = name.isEmpty ? "+\(phoneDigits)" : name
        } else {
            card.givenName = given
            card.familyName = family
        }
        card.phoneNumbers = [
            CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: "+\(phoneDigits)")),
        ]
        if let imageData = seed.imageData {
            card.imageData = imageData
        }
        let container = store.defaultContainerIdentifier()
        let save = CNSaveRequest()
        save.add(card, toContainerWithIdentifier: container)
        do {
            try store.execute(save)
        } catch {
            log?("create from Recents failed · \(errorLogLabel(error))")
            throw error
        }
        let label = self.displayName(of: card)
        let photo = seed.imageData.map { " · photo \($0.count)B" } ?? ""
        log?(
            "created card from Recents · «\(label)» · +\(phoneDigits) · id=\(card.identifier.prefix(16)) · container=\(container.prefix(12))\(photo)"
        )
        RecentsNotice.record(identifier: card.identifier, name: label)
        return (try? unifiedContact(store: store, identifier: card.identifier, keysToFetch: keys)) ?? card
    }

    private static func contacts(
        withCanonicalDigits digits: String,
        store: CNContactStore,
        keysToFetch keys: [CNKeyDescriptor],
        log: ((String) -> Void)?
    ) throws -> [CNContact] {
        func hasNumber(_ contact: CNContact) -> Bool {
            contact.phoneNumbers.contains { WordApiContactPhoneParsing.number($0.value.stringValue, matchesCanonical: digits) }
        }

        var seen = Set<String>()
        var found: [CNContact] = []
        var candidates = ["+\(digits)", WordApiSettings.nationalNumber(fromCanonical: digits)]
        if digits.count > 9 { candidates.append(String(digits.suffix(9))) }
        var tried = Set<String>()
        for candidate in candidates where candidate.filter(\.isNumber).count >= 7 && tried.insert(candidate).inserted {
            let predicate = CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: candidate))
            do {
                for contact in try store.unifiedContacts(matching: predicate, keysToFetch: keys)
                where seen.insert(contact.identifier).inserted {
                    found.append(contact)
                }
            } catch {
                log?("phone predicate \(candidate) · \(errorLogLabel(error))")
            }
        }
        let exact = found.filter(hasNumber)
        if !exact.isEmpty { return exact }
        if !found.isEmpty { return found }

        var scanned = 0
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.unifyResults = true
        do {
            try store.enumerateContacts(with: request) { contact, _ in
                scanned += 1
                if hasNumber(contact) { found.append(contact) }
            }
        } catch {
            log?("enumerate · \(errorLogLabel(error))")
            throw error
        }
        log?("enumerate · scanned \(scanned) card(s) · \(found.count) with +\(digits)")
        return found
    }

    /// Unique card with a phone whose display name matches accent/case-insensitively. The name predicate is not
    /// diacritic-insensitive, so an empty predicate result falls back to a full scan.
    private static func contactByName(
        _ displayName: String?,
        store: CNContactStore,
        keysToFetch keys: [CNKeyDescriptor],
        log: ((String) -> Void)?
    ) throws -> CNContact? {
        let raw = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let wanted = normalizedName(raw)
        guard !wanted.isEmpty else { return nil }
        func matches(_ contact: CNContact) -> Bool {
            !contact.phoneNumbers.isEmpty && normalizedName(self.displayName(of: contact)) == wanted
        }
        var found: [CNContact] = []
        do {
            found = try store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: raw), keysToFetch: keys)
                .filter(matches)
        } catch {
            log?("name predicate · \(errorLogLabel(error))")
        }
        if found.isEmpty {
            var scanned = 0
            let request = CNContactFetchRequest(keysToFetch: keys)
            request.unifyResults = true
            try store.enumerateContacts(with: request) { contact, _ in
                scanned += 1
                if matches(contact) { found.append(contact) }
            }
            log?("name fallback · enumerate · scanned \(scanned) card(s)")
        }
        log?("name fallback · «\(raw)» · \(found.count) match(es) (accent/case-insensitive)")
        return found.count == 1 ? found[0] : nil
    }

    private static func bestMatch(_ matches: [CNContact], identifier: String, displayName: String?) -> CNContact {
        if matches.count == 1 { return matches[0] }
        if !identifier.isEmpty, let byID = matches.first(where: { $0.identifier == identifier }) {
            return byID
        }
        let wanted = displayName ?? ""
        if !normalizedName(wanted).isEmpty {
            if let exact = matches.first(where: { namesMatch(self.displayName(of: $0), wanted) }) {
                return exact
            }
            if let given = matches.first(where: { namesMatch($0.givenName, wanted) }) {
                return given
            }
        }
        return matches[0]
    }

    /// Resolves a unified contact by identifier (Limited Contacts on iOS 18+ only returns allowed cards).
    static func unifiedContact(
        store: CNContactStore,
        identifier: String,
        keysToFetch: [CNKeyDescriptor]
    ) throws -> CNContact {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Error.notAccessible }
        let predicate = CNContact.predicateForContacts(withIdentifiers: [trimmed])
        if let match = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch).first {
            return match
        }
        throw Error.notAccessible
    }

    static func userFacingMessage(for error: Swift.Error) -> String {
        if let fetchError = error as? Error {
            switch fetchError {
            case .notAccessible: return notAccessibleMessage
            case .transientIdentifier: return transientIdentifierMessage
            }
        }
        if let cn = error as? CNError {
            switch cn.code {
            case .recordDoesNotExist:
                return notAccessibleMessage
            case .authorizationDenied:
                return "Contacts access denied — enable in Settings → MindtoneX → Contacts."
            case .communicationError:
                return "Could not reach Contacts — try again."
            default:
                break
            }
        }
        let raw = error.localizedDescription
        if raw.localizedCaseInsensitiveContains("record does not exist") {
            return notAccessibleMessage
        }
        return raw
    }

    static let limitedAccessHint =
        "With Full Access iOS still refused this card — try Settings → MindtoneX → Contacts → Limited Access, add the spectator’s contact, then re-pick."

    /// Save/resolve failure text; under Full Access adds the CNError code and a Limited Access suggestion.
    static func saveFailureMessage(for error: Swift.Error) -> String {
        let base = userFacingMessage(for: error)
        guard isFullAccess else { return base }
        let code = (error as? CNError).map { " (CNError \($0.code.rawValue))" } ?? ""
        return "\(base)\(code) \(limitedAccessHint)"
    }
}
