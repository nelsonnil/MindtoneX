import SwiftUI

struct AlbumArtContactInputPanel: View {
    @AppStorage(AlbumArtContactSettings.Key.enabled) private var albumArtOnContact = false
    @AppStorage(AlbumArtContactSettings.Key.saveToPhotos) private var saveAlbumArtToPhotos = false

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
