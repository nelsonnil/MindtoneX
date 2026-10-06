import Contacts
import ContactsUI
import SwiftUI

struct WordApiSpectatorDialSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var phoneDraft = WordApiSettings.lastDialedPhoneDigits.isEmpty
        ? WordApiSettings.fallbackPhoneDigits
        : WordApiSettings.lastDialedPhoneDigits

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Call the spectator first. When the outgoing call ends, MindtoneX saves this number and continues to Perform.")
                    .font(.caption)
                    .foregroundStyle(OracleTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("Country code + number", text: $phoneDraft)
                    .keyboardType(.phonePad)
                    .font(.body.monospaced())
                    .padding(12)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Button {
                    startCall()
                } label: {
                    Label("Call (Phone app)", systemImage: "phone.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(OracleTheme.gold)

                Text("Waiting for hang-up… Perform starts automatically after the call ends.")
                    .font(.caption2)
                    .foregroundStyle(OracleTheme.textSecondary)

                Spacer()
            }
            .padding(20)
            .background(OracleTheme.bgTop)
            .navigationTitle("Unknown spectator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        WordApiContactPerformGate.cancelPendingPerform()
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(WordApiContactPerformGate.awaitingOutgoingEnd)
    }

    private func startCall() {
        let digits = WordApiSettings.normalizePhoneDigits(phoneDraft)
        guard digits.count >= 7 else { return }
        WordApiContactPerformGate.beginDialCapture(phoneDigits: digits)
        let tel = "tel://+\(digits)"
        guard let url = URL(string: tel) else { return }
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
        var digits = WordApiSettings.normalizePhoneDigits(raw)
        if digits.hasPrefix("00") { digits.removeFirst(2) }
        guard digits.count >= 7 else { return nil }
        return "+\(digits)"
    }
}
