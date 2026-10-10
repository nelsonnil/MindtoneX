import SwiftUI

struct AlbumArtContactInputPanel: View {
    @AppStorage(AlbumArtContactSettings.Key.enabled) private var albumArtOnContact = false
    @AppStorage(AlbumArtContactSettings.Key.saveToPhotos) private var saveAlbumArtToPhotos = false
    @AppStorage(WordApiSettings.Key.contactMode) private var contactModeRaw = WordApiSettings.ContactMode.unknown.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: $albumArtOnContact) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Album art on contact")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(OracleTheme.textPrimary)
                    Text("When a track locks during Perform, the album cover is saved to the spectator’s contact photo (center-cropped for the round incoming-call UI).")
                        .font(.caption2)
                        .foregroundStyle(OracleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("iOS shows this as the round contact photo (Recents, contact card, incoming call). A full-screen **Contact Poster** can’t be set by apps — only manually in Contacts → contact → Contact Photo & Poster.")
                        .font(.caption2)
                        .foregroundStyle(OracleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(OracleTheme.gold)
            .onChange(of: albumArtOnContact) { _, on in
                AlbumArtContactSettings.setEnabled(on)
            }

            Toggle(isOn: $saveAlbumArtToPhotos) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Save album art to Photos")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(OracleTheme.textPrimary)
                    Text("Same square crop at song lock. Saving to your Photo Library helps **lock screen predictions** — you can automate wallpaper from the latest gallery image with Shortcuts.")
                        .font(.caption2)
                        .foregroundStyle(OracleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(OracleTheme.gold)
            .onChange(of: saveAlbumArtToPhotos) { _, on in
                AlbumArtContactSettings.setSaveToPhotosEnabled(on)
            }

            if albumArtOnContact {
                contactSetupCard
                AlbumArtContactTestSection(contactModeRaw: contactModeRaw)
            } else {
                SpectatorContactExplainer()
            }
        }
    }

    private var contactSetupCard: some View {
        SpectatorContactSetupSection(
            card: .albumArtwork,
            showsRestoreToggle: true
        )
        .padding(14)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
        }
    }
}

// MARK: - Test contact photo

private struct AlbumArtContactTestSection: View {
    @EnvironmentObject private var model: AppModel
    let contactModeRaw: String

    @State private var testTrack: PreviewTrack?
    @AppStorage(AlbumArtContactSettings.Key.testContactIdentifier) private var testContactIdentifier = ""
    @AppStorage(AlbumArtContactSettings.Key.testContactDisplayName) private var testContactDisplayName = ""
    @AppStorage(AlbumArtContactSettings.Key.testContactPhoneDigits) private var testContactPhoneDigits = ""
    @AppStorage(WordApiSettings.Key.knownContactIdentifier) private var knownContactIdentifier = ""
    @AppStorage(SpectatorContactFetch.RecentsNotice.identifierKey) private var recentsCreatedIdentifier = ""
    @State private var applyOutcome: AlbumArtContactApplyOutcome?
    @State private var isApplying = false
    @State private var showTestContactPicker = false

    private var contactMode: WordApiSettings.ContactMode {
        WordApiSettings.ContactMode(rawValue: contactModeRaw) ?? .unknown
    }

    private var resolvedContactIdentifier: String? {
        if contactMode == .known, WordApiSettings.hasKnownContactSelected {
            return WordApiSettings.knownContactIdentifier
        }
        let id = testContactIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? nil : id
    }

    private var resolvedContactPhoneDigits: String {
        if contactMode == .known, WordApiSettings.hasKnownContactSelected {
            return WordApiSettings.knownContactPhoneDigits
        }
        return testContactPhoneDigits.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var usesKnownContact: Bool {
        contactMode == .known && WordApiSettings.hasKnownContactSelected
    }

    private var recentsNotice: String? {
        guard !recentsCreatedIdentifier.isEmpty else { return nil }
        return SpectatorContactFetch.RecentsNotice.message(forIdentifier: resolvedContactIdentifier)
    }

    private var resolvedContactLabel: String? {
        if contactMode == .known, WordApiSettings.hasKnownContactSelected {
            return WordApiSettings.knownContactDisplayName
        }
        let name = testContactDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private var needsTestContactPick: Bool {
        resolvedContactIdentifier == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Test contact photo")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OracleTheme.textPrimary)

            Text("Try album art on a contact without Perform — same crop and JPEG save as song lock.")
                .font(.caption2)
                .foregroundStyle(OracleTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            contactTargetRow

            VStack(alignment: .leading, spacing: 8) {
                Text("Pick a song")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OracleTheme.textSecondary)
                LibrarySongSearchBlock(
                    pickedTrackID: testTrack?.id,
                    onPick: { testTrack = $0; applyOutcome = nil },
                    resultsPresentation: .sheet
                )
                if let track = testTrack {
                    Text("Selected · \(track.title) — \(track.artist)")
                        .font(.caption)
                        .foregroundStyle(OracleTheme.textPrimary)
                        .lineLimit(2)
                }
            }

            Button {
                applyNow()
            } label: {
                Group {
                    if isApplying {
                        ProgressView()
                            .tint(OracleTheme.ink)
                    } else {
                        Text("Apply to contact now")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(OracleTheme.ink)
                .background(OracleTheme.goldGradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isApplying || testTrack == nil || needsTestContactPick)

            if let applyOutcome {
                Label(
                    applyOutcome.message,
                    systemImage: applyOutcome.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(applyOutcome.isSuccess ? OracleTheme.sectionTeal : OracleTheme.coral)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
        }
        .sheet(isPresented: $showTestContactPicker) {
            WordApiKnownContactPicker(
                onPick: { picked in
                    showTestContactPicker = false
                    let label = picked.displayName.isEmpty ? "Contact" : picked.displayName
                    AlbumArtContactSettings.saveTestContactSelection(
                        identifier: picked.contact.identifier,
                        displayName: label,
                        phoneDigits: picked.phoneE164 ?? ""
                    )
                    albumArtLog(
                        "test contact picked «\(label)» · phone=\(picked.phoneE164 ?? "none") · id=\(WordApiInputPanel.truncated(picked.contact.identifier, max: 16))"
                    )
                    if picked.createdFromRecents {
                        albumArtLog("created real card from Recents · «\(label)» · \(picked.phoneE164 ?? "no phone")")
                    }
                    testContactIdentifier = picked.contact.identifier
                    testContactDisplayName = label
                    applyOutcome = nil
                },
                onCancel: { showTestContactPicker = false }
            )
        }
    }

    @ViewBuilder
    private var contactTargetRow: some View {
        if let label = resolvedContactLabel, resolvedContactIdentifier != nil {
            Label(label, systemImage: "person.crop.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(OracleTheme.gold)
            let phone = resolvedContactPhoneDigits
            Text(phone.isEmpty ? "Phone · none saved — re-pick to store it" : "Phone · +\(phone)")
                .font(.caption.monospaced())
                .foregroundStyle(phone.isEmpty ? OracleTheme.coral : OracleTheme.textSecondary)
            if let recentsNotice {
                Label(recentsNotice, systemImage: "person.crop.circle.badge.checkmark")
                    .font(.caption2)
                    .foregroundStyle(OracleTheme.sectionTeal)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if usesKnownContact {
                Text("Using your shared Known contact.")
                    .font(.caption2)
                    .foregroundStyle(OracleTheme.textSecondary)
            } else {
                Text("Test-only contact (does not change Home Known/Unknown mode).")
                    .font(.caption2)
                    .foregroundStyle(OracleTheme.textSecondary)
                Button {
                    showTestContactPicker = true
                } label: {
                    Label("Change test contact", systemImage: "person.crop.circle.badge.plus")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(OracleTheme.gold)
            }
        } else {
            Text("Switch to **Known** and choose a contact above, or pick a contact here for this test only.")
                .font(.caption)
                .foregroundStyle(OracleTheme.coral)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                showTestContactPicker = true
            } label: {
                Label("Pick contact for test", systemImage: "person.crop.circle.badge.plus")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(OracleTheme.gold)
        }
    }

    @MainActor
    private func applyNow() {
        guard let track = testTrack else {
            albumArtLog("button blocked · no track selected")
            applyOutcome = .failure("Pick a song first.")
            return
        }
        guard let contactID = resolvedContactIdentifier else {
            albumArtLog("button blocked · no contact")
            applyOutcome = .failure("Pick a contact for this test.")
            return
        }
        let label = resolvedContactLabel ?? "Contact"
        applyOutcome = nil
        isApplying = true
        model.runAlbumArtContactTestApply(
            track: track,
            contactIdentifier: contactID,
            contactPhoneDigits: resolvedContactPhoneDigits,
            contactDisplayName: label
        ) { outcome in
            applyOutcome = outcome
            isApplying = false
        }
    }
}

struct AlbumArtContactHomeCard: View {
    @AppStorage(AlbumArtContactSettings.Key.enabled) private var albumArtOnContact = false
    @AppStorage(AlbumArtContactSettings.Key.saveToPhotos) private var saveAlbumArtToPhotos = false
    @AppStorage(WordApiSettings.Key.contactMode) private var contactModeRaw = WordApiSettings.ContactMode.unknown.rawValue

    private var summary: String {
        if !albumArtOnContact && !saveAlbumArtToPhotos {
            return "Off — no album art saved at song lock"
        }
        var parts: [String] = []
        if albumArtOnContact {
            parts.append(contactSummary)
        }
        if saveAlbumArtToPhotos {
            parts.append("Photos")
        }
        return parts.joined(separator: " · ")
    }

    private var contactSummary: String {
        let mode = WordApiSettings.ContactMode(rawValue: contactModeRaw) ?? .unknown
        switch mode {
        case .known:
            if WordApiSettings.hasKnownContactSelected {
                return "Contact · «\(WordApiSettings.knownContactDisplayName)»"
            }
            return "Contact · pick on Home"
        case .unknown:
            if !WordApiSettings.lastDialedPhoneDigits.isEmpty {
                return "Contact · +\(WordApiSettings.lastDialedPhoneDigits)"
            }
            return "Contact · dial on Perform"
        }
    }

    var body: some View {
        CollapsibleHomeSection(
            expandedKey: HomeSectionExpandKey.albumArtContact,
            accent: OracleTheme.sectionSlate,
            icon: "music.note.list",
            title: "Album artwork",
            summary: summary,
            showsRevelationStar: true
        ) {
            AlbumArtContactInputPanel()
        }
    }
}
