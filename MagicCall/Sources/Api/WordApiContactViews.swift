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
            let store = CNContactStore()
            let keys: [CNKeyDescriptor] = [
                CNContactIdentifierKey as CNKeyDescriptor,
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactPhoneNumbersKey as CNKeyDescriptor,
            ]
            if let full = try? SpectatorContactFetch.unifiedContact(
                store: store,
                identifier: contact.identifier,
                keysToFetch: keys
            ) {
                onPick(full)
            } else {
                onPick(contact)
            }
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            onCancel()
        }
    }
}

enum WordApiContactPhoneParsing {
    static func e164(from contact: CNContact) -> String? {
        guard let raw = contact.phoneNumbers.first?.value.stringValue else { return nil }
        let digits = WordApiSettings.canonicalPhoneDigits(raw)
        guard digits.count >= 7 else { return nil }
        return "+\(digits)"
    }
}

// MARK: - Fetch / user-facing Contacts errors

enum SpectatorContactFetch {
    static let notAccessibleMessage =
        "Contact not accessible — re-pick in Known mode or grant full Contacts access."

    enum Error: Swift.Error {
        case notAccessible
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
        if error is Error { return notAccessibleMessage }
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
