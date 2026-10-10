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

struct WordApiKnownContactPicker: UIViewControllerRepresentable {
    var onPick: (CNContact) -> Void
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
        let onPick: (CNContact) -> Void
        let onCancel: () -> Void

        init(onPick: @escaping (CNContact) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let phone = WordApiContactPhoneParsing.e164(from: contact)
            guard let resolved = try? SpectatorContactFetch.resolveContact(
                store: CNContactStore(),
                identifier: contact.identifier,
                phoneDigits: phone,
                displayName: SpectatorContactFetch.displayName(of: contact),
                keysToFetch: []
            ) else {
                dlog("[CONTACT] picker · unified lookup failed · id=\(WordApiInputPanel.truncated(contact.identifier, max: 16))")
                onPick(contact)
                return
            }
            if resolved.contact.identifier != contact.identifier {
                dlog(
                    "[CONTACT] picker · id \(WordApiInputPanel.truncated(contact.identifier, max: 16)) → unified \(WordApiInputPanel.truncated(resolved.contact.identifier, max: 16)) (by phone)"
                )
            }
            onPick(resolved.contact)
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            onCancel()
        }
    }
}

enum WordApiContactPhoneParsing {
    static func e164(from contact: CNContact) -> String? {
        guard contact.isKeyAvailable(CNContactPhoneNumbersKey),
              let raw = contact.phoneNumbers.first?.value.stringValue else { return nil }
        let digits = WordApiSettings.canonicalPhoneDigits(raw)
        guard digits.count >= 7 else { return nil }
        return "+\(digits)"
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

    struct Resolution {
        let contact: CNContact
        let resolvedByPhone: Bool
        let phoneMatchCount: Int
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

    private static let matchKeys: [CNKeyDescriptor] = [
        CNContactIdentifierKey as CNKeyDescriptor,
        CNContactGivenNameKey as CNKeyDescriptor,
        CNContactFamilyNameKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor,
    ]

    /// Unified store card for save: durable id first, else phone (disambiguated by id, then display name).
    static func resolveContact(
        store: CNContactStore,
        identifier: String?,
        phoneDigits: String?,
        displayName: String?,
        keysToFetch: [CNKeyDescriptor]
    ) throws -> Resolution {
        let keys = keysToFetch + matchKeys
        let id = (identifier ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let transient = isTransientIdentifier(id)
        if !id.isEmpty, !transient,
           let match = try? unifiedContact(store: store, identifier: id, keysToFetch: keys) {
            return Resolution(contact: match, resolvedByPhone: false, phoneMatchCount: 0)
        }
        let digits = WordApiSettings.canonicalPhoneDigits(phoneDigits ?? "")
        guard digits.count >= 7 else {
            throw transient ? Error.transientIdentifier : Error.notAccessible
        }
        let matches = try contacts(withCanonicalDigits: digits, store: store, keysToFetch: keys)
        guard !matches.isEmpty else { throw Error.notAccessible }
        let pick = bestMatch(matches, identifier: id, displayName: displayName)
        return Resolution(contact: pick, resolvedByPhone: true, phoneMatchCount: matches.count)
    }

    /// Known-mode card from saved settings; persists the unified id when re-resolved by phone.
    static func resolveKnownContact(store: CNContactStore, keysToFetch: [CNKeyDescriptor]) throws -> Resolution {
        let stored = WordApiSettings.knownContactIdentifier
        let resolution = try resolveContact(
            store: store,
            identifier: stored,
            phoneDigits: WordApiSettings.knownContactPhoneDigits,
            displayName: WordApiSettings.knownContactDisplayName,
            keysToFetch: keysToFetch
        )
        if resolution.contact.identifier != stored {
            WordApiSettings.updateKnownContactIdentifier(resolution.contact.identifier)
        }
        return resolution
    }

    private static func contacts(
        withCanonicalDigits digits: String,
        store: CNContactStore,
        keysToFetch keys: [CNKeyDescriptor]
    ) throws -> [CNContact] {
        let region = WordApiSettings.deviceRegionISO
        func hasNumber(_ contact: CNContact) -> Bool {
            contact.phoneNumbers.contains {
                WordApiSettings.canonicalPhoneDigits($0.value.stringValue, region: region) == digits
            }
        }

        var seen = Set<String>()
        var found: [CNContact] = []
        let national = WordApiSettings.nationalNumber(fromCanonical: digits)
        for candidate in Set(["+\(digits)", national]) where candidate.filter(\.isNumber).count >= 7 {
            let predicate = CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: candidate))
            for contact in try store.unifiedContacts(matching: predicate, keysToFetch: keys)
            where seen.insert(contact.identifier).inserted {
                found.append(contact)
            }
        }
        let exact = found.filter(hasNumber)
        if !exact.isEmpty { return exact }
        if !found.isEmpty { return found }

        let request = CNContactFetchRequest(keysToFetch: keys)
        request.unifyResults = true
        try store.enumerateContacts(with: request) { contact, _ in
            if hasNumber(contact) { found.append(contact) }
        }
        return found
    }

    private static func bestMatch(_ matches: [CNContact], identifier: String, displayName: String?) -> CNContact {
        if matches.count == 1 { return matches[0] }
        if !identifier.isEmpty, let byID = matches.first(where: { $0.identifier == identifier }) {
            return byID
        }
        let wanted = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !wanted.isEmpty {
            if let exact = matches.first(where: { self.displayName(of: $0).caseInsensitiveCompare(wanted) == .orderedSame }) {
                return exact
            }
            if let given = matches.first(where: {
                $0.givenName.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(wanted) == .orderedSame
            }) {
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
}
