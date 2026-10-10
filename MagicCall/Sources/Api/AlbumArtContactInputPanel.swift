import SwiftUI

struct AlbumArtContactInputPanel: View {
    @AppStorage(AlbumArtContactSettings.Key.enabled) private var albumArtEnabled = false
    @AppStorage(WordApiSettings.Key.contactMode) private var contactModeRaw = WordApiSettings.ContactMode.unknown.rawValue
    @AppStorage(WordApiSettings.Key.restoreKnownNameOnSettingsExit) private var restoreAfterPerform = true

    @State private var showContactPicker = false
    @State private var manualPhoneDigits = ""

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
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: $albumArtEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Album art on contact")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(OracleTheme.textPrimary)
                    Text("When the song locks, the album cover is saved to the spectator’s contact photo (center-cropped for the round incoming-call UI).")
                        .font(.caption2)
                        .foregroundStyle(OracleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(OracleTheme.gold)
            .onChange(of: albumArtEnabled) { _, on in
                AlbumArtContactSettings.setEnabled(on)
            }

            if albumArtEnabled {
                setupCard
            }
        }
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Uses the **same phone and contact** as **Caller name** (Known / Unknown). Set it here or on the Caller name card — they stay in sync.")
                .font(.caption)
                .foregroundStyle(OracleTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Which contact gets the photo")
                .font(.caption.weight(.semibold))
                .foregroundStyle(OracleTheme.textPrimary)

            WordContactModePicker(selection: contactModeBinding)

            Text(contactMode == .unknown ? unknownDetail : knownDetail)
                .font(.caption2)
                .foregroundStyle(OracleTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .animation(.easeInOut(duration: 0.2), value: contactModeRaw)

            if contactMode == .known {
                knownContactBlock
            } else {
                unknownContactBlock
            }

            Toggle(isOn: $restoreAfterPerform) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Restore contact photo after Perform")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(OracleTheme.textPrimary)
                    Text("When you leave Perform or close settings, revert the contact photo MindtoneX changed at song lock.")
                        .font(.caption2)
                        .foregroundStyle(OracleTheme.textSecondary)
                }
            }
            .tint(OracleTheme.gold)
            .onChange(of: restoreAfterPerform) { _, on in
                WordApiSettings.setRestoreKnownNameOnSettingsExit(on)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
        }
        .sheet(isPresented: $showContactPicker) {
            WordApiKnownContactPicker(
                onPick: { contact in
                    showContactPicker = false
                    if let e164 = WordApiContactPhoneParsing.e164(from: contact) {
                        SpectatorWordContactService.recordKnownContactPicked(contact, phoneE164: e164)
                    }
                },
                onCancel: { showContactPicker = false }
            )
        }
    }

    private var unknownDetail: String {
        "We need the spectator’s phone number **before the show** so we can create or update the contact that will show the album image on the incoming call. On Perform, MindtoneX opens the in-app dial (real outgoing call) to capture that number — or enter it below for setup."
    }

    private var knownDetail: String {
        "Pick the contact card that should display the album artwork when they call back."
    }

    private var knownContactBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            if WordApiSettings.hasKnownContactSelected {
                Text("Contact used for album art:")
                    .font(.caption)
                    .foregroundStyle(OracleTheme.textSecondary)
                Label(WordApiSettings.knownContactDisplayName, systemImage: "person.crop.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OracleTheme.gold)
                Text("Phone · +\(WordApiSettings.knownContactPhoneDigits)")
                    .font(.caption.monospaced())
                    .foregroundStyle(OracleTheme.textSecondary)
            } else {
                Text("Choose a contact before Perform.")
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
            .foregroundStyle(OracleTheme.gold)
        }
    }

    private var unknownContactBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dial or enter number")
                .font(.caption.weight(.semibold))
                .foregroundStyle(OracleTheme.textPrimary)

            TextField(WordApiSettings.phoneDisplayPlaceholder(), text: $manualPhoneDigits)
                .keyboardType(.phonePad)
                .font(.body.monospaced())
                .foregroundStyle(OracleTheme.textPrimary)
                .padding(10)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onChange(of: manualPhoneDigits) { _, newValue in
                    let digits = WordApiSettings.canonicalPhoneDigits(newValue)
                    if digits.count >= 7 {
                        WordApiSettings.setLastDialedPhoneDigits(digits)
                    }
                }

            Text(WordApiSettings.phoneEntryHint())
                .font(.caption2)
                .foregroundStyle(OracleTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if !WordApiSettings.lastDialedPhoneDigits.isEmpty {
                Text("Saved · +\(WordApiSettings.lastDialedPhoneDigits)")
                    .font(.caption.monospaced())
                    .foregroundStyle(OracleTheme.gold)
            } else {
                Text("No number yet — Perform opens the dial first, or type the mobile here.")
                    .font(.caption)
                    .foregroundStyle(OracleTheme.textSecondary)
            }
        }
        .onAppear {
            if !WordApiSettings.lastDialedPhoneDigits.isEmpty {
                manualPhoneDigits = WordApiSettings.formatPhoneForDisplay(WordApiSettings.lastDialedPhoneDigits)
            }
        }
    }
}

struct AlbumArtContactHomeCard: View {
    @AppStorage(AlbumArtContactSettings.Key.enabled) private var albumArtEnabled = false
    @AppStorage(WordApiSettings.Key.contactMode) private var contactModeRaw = WordApiSettings.ContactMode.unknown.rawValue

    private var summary: String {
        guard albumArtEnabled else { return "Off — incoming call uses the contact’s existing photo" }
        let mode = WordApiSettings.ContactMode(rawValue: contactModeRaw) ?? .unknown
        switch mode {
        case .known:
            if WordApiSettings.hasKnownContactSelected {
                return "On · «\(WordApiSettings.knownContactDisplayName)»"
            }
            return "On · Known — pick a contact"
        case .unknown:
            if !WordApiSettings.lastDialedPhoneDigits.isEmpty {
                return "On · +\(WordApiSettings.lastDialedPhoneDigits)"
            }
            return "On · Unknown — dial or enter number before Perform"
        }
    }

    var body: some View {
        CollapsibleHomeSection(
            expandedKey: HomeSectionExpandKey.albumArtContact,
            accent: OracleTheme.sectionSlate,
            icon: "music.note.list",
            title: "Album art on contact",
            summary: summary,
            showsRevelationStar: true
        ) {
            AlbumArtContactInputPanel()
        }
    }
}
