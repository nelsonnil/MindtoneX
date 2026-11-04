import Contacts
import ContactsUI
import SwiftUI

/// Spotlight song-input settings shown in the song strip.
struct SpotlightInputControls: View {
    @ObservedObject private var icons = SpotlightAppIconStore.shared
    @AppStorage(SpotlightSettings.Key.contactName) private var contactName = ""
    @AppStorage(SpotlightSettings.Key.disguiseText) private var disguiseText = ""
    @AppStorage(SpotlightSettings.Key.suggestedApps) private var suggestedAppsRaw = ""
    @AppStorage(SpotlightSettings.Key.browser) private var browserRaw = SpotlightSettings.Browser.safari.rawValue
    @AppStorage(SpectatorSettings.Key.count) private var songCount = 1
    @AppStorage(InterferenceSettings.Key.enabled) private var interferenceEnabled = false
    @State private var pickingContact = false
    @State private var contactsReadable = SpotlightSession.contactsReadable

    private var selectedApps: [String] { SpotlightSettings.decodeApps(suggestedAppsRaw) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(.init("Perform shows your home screen. **Swipe down** to open Spotlight and say you are looking for your contact. Type the **song**: the search bar shows your contact’s name, one letter per key. **Tapping your contact** to show the card is what searches the song (exactly as typed); the incoming call plays it."))
                .font(.caption)
                .foregroundStyle(OracleTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if interferenceEnabled, songCount == 2 {
                Text(.init("**2 songs:** type song 1, a **double space**, then song 2 — e.g. `rihanna  michael jackson`."))
                    .font(.caption)
                    .foregroundStyle(OracleTheme.gold)
                    .fixedSize(horizontal: false, vertical: true)
            }

            OracleEyebrow(text: "Your contact")
            card {
                Button { pickingContact = true } label: {
                    HStack {
                        Image(systemName: "person.crop.circle")
                            .font(.title3)
                        Text(contactName.isEmpty ? "Choose contact" : contactName)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(OracleTheme.textSecondary)
                    }
                    .foregroundStyle(OracleTheme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                rowDivider

                VStack(alignment: .leading, spacing: 6) {
                    Text("Text in the search bar")
                        .font(.subheadline)
                        .foregroundStyle(OracleTheme.textPrimary)
                    TextField(SpotlightSettings.defaultDisguise(for: contactName.isEmpty ? "Nelson Suarez" : contactName),
                              text: $disguiseText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.subheadline.monospaced())
                        .foregroundStyle(OracleTheme.textPrimary)
                    Text("Extra key presses after the last letter are still typed into the song search, but nothing more appears on screen.")
                        .font(.caption)
                        .foregroundStyle(OracleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }

            if !contactsReadable {
                Button(action: requestContacts) {
                    Label("Contacts access is off: the contact card may not open. Tap to allow.", systemImage: "person.2.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(OracleTheme.gold)
                }
                .buttonStyle(.plain)
            }

            OracleEyebrow(text: "Browser in Suggestions")
            Picker("Browser", selection: $browserRaw) {
                ForEach(SpotlightSettings.Browser.allCases) { browser in
                    Text(browser.title).tag(browser.rawValue)
                }
            }
            .pickerStyle(.segmented)

            OracleEyebrow(text: "Siri Suggestions · \(selectedApps.count)/\(SpotlightSettings.suggestedAppCount)")
            appPicker
            Text("Icons and Apple app names come from the App Store in your iPhone’s language. Tap to add or remove; the first 8 in order are shown.")
                .font(.caption2)
                .foregroundStyle(OracleTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            contactsReadable = SpotlightSession.contactsReadable
            SpotlightAppIconStore.shared.prefetch(SpotlightAppCatalog.apps.map(\.bundleId))
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            contactsReadable = SpotlightSession.contactsReadable
        }
        .sheet(isPresented: $pickingContact) {
            SpotlightContactPicker { contact in
                let changed = contact.identifier != SpotlightSettings.contactIdentifier
                SpotlightSettings.saveContact(identifier: contact.identifier, name: SpotlightSession.displayName(of: contact))
                SpotlightSettings.savePickedCard(contact)
                contactName = SpotlightSettings.contactName
                // A custom search-bar text belongs to the old contact; the new one starts from its own name.
                if changed { disguiseText = "" }
                SpotlightSession.shared.reset()
                pickingContact = false
                if !contactsReadable { requestContacts() }
            } onCancel: {
                pickingContact = false
            }
            .ignoresSafeArea()
        }
    }

    private var appPicker: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(SpotlightAppCatalog.apps) { app in
                let index = selectedApps.firstIndex(of: app.bundleId)
                Button { toggle(app.bundleId) } label: {
                    VStack(spacing: 4) {
                        SpotlightAppIcon(bundleId: app.bundleId, size: 46)
                            .overlay(alignment: .topTrailing) {
                                if let index {
                                    Text("\(index + 1)")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.black)
                                        .frame(width: 18, height: 18)
                                        .background(OracleTheme.gold, in: Circle())
                                        .offset(x: 5, y: -5)
                                }
                            }
                            .opacity(index == nil ? 0.45 : 1)
                        Text(icons.name(for: app.bundleId))
                            .font(.system(size: 10))
                            .lineLimit(1)
                            .foregroundStyle(OracleTheme.textSecondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func toggle(_ bundleId: String) {
        var apps = selectedApps
        if let index = apps.firstIndex(of: bundleId) {
            apps.remove(at: index)
        } else if apps.count < SpotlightSettings.suggestedAppCount {
            apps.append(bundleId)
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        suggestedAppsRaw = SpotlightSettings.encodeApps(apps)
    }

    private func requestContacts() {
        // Once denied, iOS never asks again; only the Settings app can turn it back on.
        if CNContactStore.authorizationStatus(for: .contacts) == .denied,
           let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
            return
        }
        CNContactStore().requestAccess(for: .contacts) { _, _ in
            DispatchQueue.main.async { contactsReadable = SpotlightSession.contactsReadable }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
            }
    }

    private var rowDivider: some View {
        Divider().overlay(OracleTheme.cardBorder).padding(.leading, 14)
    }
}

private struct SpotlightContactPicker: UIViewControllerRepresentable {
    var onPick: (CNContact) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let parent: SpotlightContactPicker
        init(parent: SpotlightContactPicker) { self.parent = parent }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            parent.onPick(contact)
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            parent.onCancel()
        }
    }
}
