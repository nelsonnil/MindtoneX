import Contacts
import ContactsUI
import SwiftUI

struct WordApiSpectatorDialSheet: View {
    @EnvironmentObject private var model: AppModel
    @State private var phoneDraft = WordApiSettings.lastDialedPhoneDigits.isEmpty
        ? WordApiSettings.fallbackPhoneDigits
        : WordApiSettings.lastDialedPhoneDigits

    var body: some View {
        WordApiIOSPhoneDialView(
            phoneDigits: $phoneDraft,
            onCancel: {
                WordApiContactPerformGate.cancelPendingPerform()
                model.wordSpectatorDialSheet = false
            },
            onCall: startCall,
            cancelEnabled: !WordApiContactPerformGate.awaitingOutgoingEnd
        )
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
            if let full = try? store.unifiedContact(withIdentifier: contact.identifier, keysToFetch: keys) {
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
