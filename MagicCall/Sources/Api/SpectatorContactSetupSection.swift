import SwiftUI

/// Which home card shows the shared Unknown / Known spectator contact block.
enum SpectatorContactHomeCard: String {
    case callerName
    case albumArtwork
    case notesContact

    /// What happens on the spectator's card when the word / song locks.
    func modeDetailLine(for mode: WordApiSettings.ContactMode) -> String {
        switch (self, mode) {
        case (.callerName, .unknown):
            return "When the word locks, the card for the number you dialed shows the word as its name."
        case (.callerName, .known):
            return "When the word locks, this card’s first name becomes the word."
        case (.albumArtwork, .unknown):
            return "When the song locks, the album cover becomes the photo of the number you dialed."
        case (.albumArtwork, .known):
            return "When the song locks, the album cover becomes this card’s photo."
        case (.notesContact, .unknown):
            return "When the word locks, your note goes in **Contacts → Notes** for the number you dialed."
        case (.notesContact, .known):
            return "When the word locks, your note goes in **Contacts → Notes** on this card."
        }
    }

    var modeSectionTitle: String {
        switch self {
        case .callerName: return "How to link the number"
        case .albumArtwork: return "Which contact gets the photo"
        case .notesContact: return "Which contact gets the note"
        }
    }
}

/// Shared Unknown | Known picker + contact status (Home cards).
struct SpectatorContactSetupSection: View {
    let card: SpectatorContactHomeCard
    var accent: Color = OracleTheme.gold
    var showsRestoreToggle: Bool = false

    @AppStorage(WordApiSettings.Key.contactMode) private var contactModeRaw = WordApiSettings.ContactMode.unknown.rawValue
    @AppStorage(WordApiSettings.Key.restoreKnownNameOnSettingsExit) private var restoreAfterPerform = true
    @AppStorage(WordApiSettings.Key.knownContactIdentifier) private var knownContactIdentifier = ""
    @AppStorage(WordApiSettings.Key.knownContactPhoneDigits) private var knownContactPhoneDigits = ""
    @AppStorage(SpectatorContactFetch.RecentsNotice.identifierKey) private var recentsCreatedIdentifier = ""

    @State private var showContactPicker = false

    private var recentsNotice: String? {
        guard !recentsCreatedIdentifier.isEmpty else { return nil }
        return SpectatorContactFetch.RecentsNotice.message(forIdentifier: knownContactIdentifier)
    }

    private var contactMode: WordApiSettings.ContactMode {
        WordApiSettings.ContactMode(rawValue: contactModeRaw) ?? .unknown
    }

    private var contactModeBinding: Binding<WordApiSettings.ContactMode> {
        Binding(
            get: { WordApiSettings.ContactMode(rawValue: contactModeRaw) ?? .unknown },
            set: { mode in
                contactModeRaw = mode.rawValue
                WordApiSettings.setContactMode(mode)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SpectatorContactExplainer(accent: accent)

            Text(card.modeSectionTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(OracleTheme.textPrimary)

            WordContactModePicker(selection: contactModeBinding)

            Text(.init(card.modeDetailLine(for: contactMode)))
                .font(.caption2)
                .foregroundStyle(OracleTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .animation(.easeInOut(duration: 0.2), value: contactModeRaw)

            if contactMode == .known {
                knownContactBlock
            } else {
                unknownContactBlock
            }

            if showsRestoreToggle {
                restoreToggle
            }
        }
        .sheet(isPresented: $showContactPicker) {
            WordApiKnownContactPicker(
                onPick: { picked in
                    showContactPicker = false
                    if let e164 = picked.phoneE164 {
                        SpectatorWordContactService.recordKnownContactPicked(picked, phoneE164: e164)
                    } else {
                        contactLog("known pick «\(picked.displayName)» rejected · no usable phone")
                        PerformUserLog.shared.log("That contact has no usable phone number")
                    }
                },
                onCancel: { showContactPicker = false }
            )
        }
    }

    private var knownContactBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            if WordApiSettings.hasKnownContactSelected {
                Label(WordApiSettings.knownContactDisplayName, systemImage: "person.crop.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
                Text("Phone · +\(knownContactPhoneDigits)")
                    .font(.caption.monospaced())
                    .foregroundStyle(OracleTheme.textSecondary)
                if let recentsNotice {
                    Label(recentsNotice, systemImage: "person.crop.circle.badge.checkmark")
                        .font(.caption2)
                        .foregroundStyle(OracleTheme.sectionTeal)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Perform goes straight to the stage — no dial pad.")
                    .font(.caption2)
                    .foregroundStyle(OracleTheme.textSecondary)
            } else {
                Text("Choose the spectator’s contact before Perform (or when prompted).")
                    .font(.caption)
                    .foregroundStyle(OracleTheme.coral)
            }

            Button {
                showContactPicker = true
            } label: {
                Label(
                    WordApiSettings.hasKnownContactSelected ? "Change contact" : "Choose contact",
                    systemImage: "person.crop.circle.badge.plus"
                )
                .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(accent)
        }
    }

    private var unknownContactBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !WordApiSettings.lastDialedPhoneDigits.isEmpty {
                Text("Last dialed · +\(WordApiSettings.lastDialedPhoneDigits)")
                    .font(.caption.monospaced())
                    .foregroundStyle(OracleTheme.textSecondary)
            } else {
                Text("No number yet — you’ll dial it when you tap Perform.")
                    .font(.caption)
                    .foregroundStyle(OracleTheme.textSecondary)
            }
        }
    }

    private var restoreToggle: some View {
        Toggle(isOn: $restoreAfterPerform) {
            VStack(alignment: .leading, spacing: 2) {
                Text(restoreTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OracleTheme.textPrimary)
                Text(restoreDetail)
                    .font(.caption2)
                    .foregroundStyle(OracleTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(accent)
        .onChange(of: restoreAfterPerform) { _, on in
            WordApiSettings.setRestoreKnownNameOnSettingsExit(on)
        }
    }

    private var restoreTitle: String {
        switch card {
        case .albumArtwork:
            return "Restore contact photo after Perform"
        case .callerName, .notesContact:
            return "Restore contact names after Perform"
        }
    }

    private var restoreDetail: String {
        switch card {
        case .albumArtwork:
            return "When you leave Perform or close settings, revert the contact photo MindtoneX changed when album art was saved."
        case .callerName, .notesContact:
            return "When you exit Perform, revert Contacts changed at word lock (or delete a contact created for the show)."
        }
    }
}

/// Home-only "why a contact?" explainer shared by Caller name, Album artwork and Notes contact. Never shown during
/// Perform: the dial pad must look like the stock Phone app.
struct SpectatorContactExplainer: View {
    var accent: Color = OracleTheme.gold

    @AppStorage(WordApiSettings.Key.contactMode) private var contactModeRaw = WordApiSettings.ContactMode.unknown.rawValue

    private var mode: WordApiSettings.ContactMode {
        WordApiSettings.ContactMode(rawValue: contactModeRaw) ?? .unknown
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row(
                icon: "music.note",
                text: "**Song / ringtone** works on its own — no contact needed."
            )
            row(
                icon: "person.crop.circle.badge.exclamationmark",
                text: "**Caller name, Album artwork, Notes** need the spectator’s contact card **before** they call you. Two ways:"
            )

            WordContactModePicker(selection: .constant(mode), mini: true)
                .accessibilityHidden(true)

            HStack(alignment: .top, spacing: 10) {
                ForEach(WordApiSettings.ContactMode.allCases) { option in
                    Text(.init(Self.howTo(option)))
                        .font(.caption2)
                        .foregroundStyle(OracleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .opacity(option == mode ? 1 : 0.55)
                        .accessibilityLabel("\(option.title): \(Self.howTo(option).replacingOccurrences(of: "**", with: ""))")
                }
            }

            Label {
                Text("Say: *“I’m calling so you can call me back at the end of the show.”* MindtoneX saves the number and creates their card.")
                    .font(.caption2)
                    .foregroundStyle(OracleTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "quote.bubble.fill")
                    .font(.caption)
                    .foregroundStyle(accent)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(mode == .unknown ? 1 : 0.55)

            Text("Same choice on all three cards.")
                .font(.caption2)
                .foregroundStyle(OracleTheme.textSecondary)
        }
        .padding(12)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(OracleTheme.cardBorder, lineWidth: 0.5)
        }
        .animation(.easeInOut(duration: 0.2), value: contactModeRaw)
    }

    private static func howTo(_ mode: WordApiSettings.ContactMode) -> String {
        switch mode {
        case .unknown: return "Tap **Perform** — a dial pad opens. Call your spectator from it."
        case .known: return "Pick their contact on this card before the show."
        }
    }

    private func row(icon: String, text: String) -> some View {
        Label {
            Text(.init(text))
                .font(.caption)
                .foregroundStyle(OracleTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(accent)
        }
    }
}
