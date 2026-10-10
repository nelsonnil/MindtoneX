import SwiftUI

/// Which home card shows the shared Unknown / Known spectator contact block.
enum SpectatorContactHomeCard: String {
    case callerName
    case albumArtwork
    case notesContact

    var syncHint: String {
        "**Unknown** and **Known** are shared on **Caller name**, **Album artwork**, and **Notes contact** only — not on the Song card. Change mode or contact on any of those three; the others follow."
    }

    func whyContactNeededParagraph(mode: WordApiSettings.ContactMode) -> String {
        switch (self, mode) {
        case (.callerName, .unknown):
            return "Before they call you back, iOS needs a **Contacts card for their number** so the locked word can show as the caller name. **Unknown:** on **Perform**, MindtoneX shows an in-app Phone dial — you make a **real outgoing call**, the app **saves the number**, and **creates or updates** that contact. **Known:** pick their card below instead."
        case (.callerName, .known):
            return "Before they call you back, iOS needs their **Contacts card** so the locked word can replace the name on the incoming call. **Choose contact** below — same person as Album artwork and Notes contact."
        case (.albumArtwork, .unknown):
            return "Album art goes on the spectator’s **contact photo** (round image on the incoming call). You need their **Contacts card** first. **Unknown:** capture the number on **Perform** with the in-app dial (real outgoing call) — **no typing a number on Home**. **Known:** pick their card below."
        case (.albumArtwork, .known):
            return "Album art is saved to the **contact photo** on the card you pick below — the same contact as Caller name and Notes contact."
        case (.notesContact, .unknown):
            return "Your text goes in **Contacts → Notes** on the spectator’s card. You need that **Contacts card** before the callback. **Unknown:** capture the number on **Perform** with the in-app dial (real outgoing call) — **no typing a number on Home**. **Known:** pick their card below."
        case (.notesContact, .known):
            return "Your note is saved on the **Contacts card** you pick below — the same contact as Caller name and Album artwork."
        }
    }

    func modeDetailLine(for mode: WordApiSettings.ContactMode) -> String {
        switch (self, mode) {
        case (.callerName, .unknown):
            return "Perform dial → real call → number saved. When the word locks: create a new contact or update every card with that number — first name becomes the word."
        case (.callerName, .known):
            return "Pick their card before Perform. When the word locks: rename **that card only** (first name → word)."
        case (.albumArtwork, .unknown):
            return "Perform dial → real call → number saved. When the track locks: album art is written to that contact’s photo."
        case (.albumArtwork, .known):
            return "Pick their card before Perform. When the track locks: album art is written to **that card’s photo**."
        case (.notesContact, .unknown):
            return "Perform dial → real call → number saved. When the Notes chip word locks: your note text is written to **Contacts → Notes** on that number’s card(s)."
        case (.notesContact, .known):
            return "Pick their card before Perform. When the Notes chip word locks: your note text is written to **Contacts → Notes** on that card."
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
    var showsSyncHint: Bool = true
    var showsRestoreToggle: Bool = false

    @AppStorage(WordApiSettings.Key.contactMode) private var contactModeRaw = WordApiSettings.ContactMode.unknown.rawValue
    @AppStorage(WordApiSettings.Key.restoreKnownNameOnSettingsExit) private var restoreAfterPerform = true

    @State private var showContactPicker = false

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
            if showsSyncHint {
                Text(.init(card.syncHint))
                    .font(.caption)
                    .foregroundStyle(OracleTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(card.whyContactNeededParagraph(mode: contactMode))
                .font(.caption)
                .foregroundStyle(OracleTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .animation(.easeInOut(duration: 0.2), value: contactModeRaw)

            Text(card.modeSectionTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(OracleTheme.textPrimary)

            WordContactModePicker(selection: contactModeBinding)

            Text(card.modeDetailLine(for: contactMode))
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
                Text("Phone · +\(WordApiSettings.knownContactPhoneDigits)")
                    .font(.caption.monospaced())
                    .foregroundStyle(OracleTheme.textSecondary)
                Text("Perform goes straight to the stage screenshot — no dial.")
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
            Text("On Perform: in-app **Phone-style dial** → **real outgoing call** → when the call **ends**, MindtoneX saves the number and continues to the stage.")
                .font(.caption)
                .foregroundStyle(OracleTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !WordApiSettings.lastDialedPhoneDigits.isEmpty {
                Text("Last dialed · +\(WordApiSettings.lastDialedPhoneDigits)")
                    .font(.caption.monospaced())
                    .foregroundStyle(OracleTheme.textSecondary)
            } else {
                Text("No number saved yet — Perform opens the dial first.")
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
