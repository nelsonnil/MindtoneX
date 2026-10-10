import SwiftUI

/// Instructions — tabbed like Home (Overview + Song, Caller name, Album, Notes).
struct PerformanceGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onOpenFavorites: () -> Void

    @State private var selectedTab: PerformanceGuideTab = .overview

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                guideHero
                guideTabPicker
                tabContent
            }
            .padding(20)
            .animation(.easeInOut(duration: 0.2), value: selectedTab)
        }
        .background(OracleTheme.bgTop)
        .navigationTitle("Instructions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
                    .foregroundStyle(OracleTheme.gold)
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .overview:
            overviewTab
        case .song:
            songTab
        case .callerName:
            callerNameTab
        case .album:
            albumTab
        case .notes:
            notesTab
        }
    }

    // MARK: - Overview

    private var overviewTab: some View {
        VStack(alignment: .leading, spacing: 22) {
            InstructionSection(
                title: "Facebook users group",
                icon: "person.3.fill",
                tint: OracleTheme.sectionTeal,
                lines: PerformInstructionsCopy.facebookUsersGroup
            )

            Link(destination: URL(string: PerformInstructionsCopy.facebookUsersGroupURL)!) {
                Label("Open Facebook group", systemImage: "arrow.up.forward.app")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .tint(OracleTheme.gold)

            InstructionSection(
                title: "iPhone setup (do this first)",
                icon: "iphone.gen3.radiowaves.left.and.right",
                tint: OracleTheme.coral,
                lines: PerformInstructionsCopy.iphoneSetupRequired
            )

            InstructionSection(
                title: "How the trick works",
                icon: "sparkles",
                tint: OracleTheme.gold,
                lines: PerformInstructionsCopy.howTheTrickWorks
            )

            InstructionSection(
                title: "Performance settings",
                icon: "photo.on.rectangle.angled",
                tint: OracleTheme.gold,
                lines: PerformInstructionsCopy.performanceSettings
            )

            InstructionSection(
                title: "During Perform",
                icon: "play.circle.fill",
                tint: OracleTheme.indigo,
                lines: PerformInstructionsCopy.duringPerform
            )

            InstructionSection(
                title: "Contact setup (Caller, Album, Notes)",
                icon: "person.crop.circle.badge.questionmark",
                tint: OracleTheme.sectionTeal,
                lines: PerformInstructionsCopy.contactSetupOverview
            )

            SpectatorContactExplainer(accent: OracleTheme.sectionTeal, placement: .instructions)

            performExitHint
        }
    }

    // MARK: - Song

    private var songTab: some View {
        VStack(alignment: .leading, spacing: 22) {
            InstructionSection(
                title: "Song",
                icon: "music.note.list",
                tint: OracleTheme.indigo,
                lines: PerformInstructionsCopy.songInputOverview
            )

            InstructionSubsection(
                title: "No contact needed",
                lines: PerformInstructionsCopy.songNoContactNote
            )

            InstructionSubsection(title: "Camera (handwriting OCR)", lines: PerformInstructionsCopy.songInputCamera)
            InstructionSubsection(
                title: "Voice (AI)",
                lines: PerformInstructionsCopy.songInputVoice(lockSeconds: Int(VoiceSettings.lockDelay))
            )
            InstructionSubsection(title: "Notes", lines: PerformInstructionsCopy.songInputNotes)
            InstructionSubsection(title: "API", lines: PerformInstructionsCopy.songInputAPI)

            InstructionSubsection(
                title: "1 or 2 songs (experimental)",
                lines: PerformInstructionsCopy.twoSongsExperimental
            )

            InstructionSubsection(
                title: "Interference ringtone",
                lines: PerformInstructionsCopy.interferenceRingtone
            )

            PerformanceGuideOptionalShare(onOpenFavorites: onOpenFavorites)

            TipCard(
                title: "Mix song + caller + Notes",
                icon: "square.stack.3d.up.fill",
                tint: OracleTheme.sectionTeal,
                lines: PerformInstructionsCopy.songInputCombinations
            )
        }
    }

    // MARK: - Caller name

    private var callerNameTab: some View {
        VStack(alignment: .leading, spacing: 22) {
            InstructionSection(
                title: "Caller name",
                icon: "phone.arrow.down.left.fill",
                tint: OracleTheme.sectionTeal,
                lines: PerformInstructionsCopy.callerName
            )

            GuideContactSetupLink()

            InstructionSubsection(
                title: "Known vs Unknown (Contacts)",
                lines: PerformInstructionsCopy.callerNameKnownUnknown
            )

            callerNameExamples
        }
    }

    private var callerNameExamples: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("On iPhone")
                .font(.caption.weight(.bold))
                .foregroundStyle(OracleTheme.textPrimary)

            InstructionAnnotatedScreenshot(
                imageName: InstructionScreenshotAsset.contactDetailFull,
                callouts: [
                    InstructionScreenshotCallout(
                        text: "This is what Caller name changes.",
                        anchor: CGPoint(x: 0.5, y: 0.278),
                        placement: .below
                    ),
                ]
            )

            InstructionAnnotatedScreenshot(
                imageName: InstructionScreenshotAsset.recentsIncoming,
                caption: "Incoming call banner shows this name and photo at the top.",
                callouts: [
                    InstructionScreenshotCallout(
                        text: "Round photo in banner",
                        anchor: CGPoint(x: 0.11, y: 0.74),
                        placement: .trailing
                    ),
                    InstructionScreenshotCallout(
                        text: "Caller name in banner",
                        anchor: CGPoint(x: 0.42, y: 0.70),
                        placement: .trailing
                    ),
                ]
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
        }
    }

    // MARK: - Album

    private var albumTab: some View {
        VStack(alignment: .leading, spacing: 22) {
            InstructionSection(
                title: "Album artwork",
                icon: "photo.on.rectangle.angled",
                tint: OracleTheme.sectionSlate,
                lines: PerformInstructionsCopy.albumArtwork
            )

            GuideContactSetupLink()

            albumArtworkExamples
        }
    }

    private var albumArtworkExamples: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("On iPhone")
                .font(.caption.weight(.bold))
                .foregroundStyle(OracleTheme.textPrimary)

            InstructionAnnotatedScreenshot(
                imageName: InstructionScreenshotAsset.contactDetailFull,
                callouts: [
                    InstructionScreenshotCallout(
                        text: "Album artwork → contact photo (shows in call banner circle).",
                        anchor: CGPoint(x: 0.5, y: 0.195),
                        placement: .below
                    ),
                ]
            )

            InstructionAnnotatedScreenshot(
                imageName: InstructionScreenshotAsset.contactDetailNotes,
                callouts: [
                    InstructionScreenshotCallout(
                        text: "Album artwork → contact photo (shows in call banner circle).",
                        anchor: CGPoint(x: 0.12, y: 0.135),
                        placement: .trailing
                    ),
                ]
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
        }
    }

    // MARK: - Notes

    private var notesTab: some View {
        VStack(alignment: .leading, spacing: 22) {
            InstructionSection(
                title: "Notes contact",
                icon: "note.text",
                tint: OracleTheme.sectionTeal,
                lines: PerformInstructionsCopy.notesContact
            )

            GuideContactSetupLink()

            notesContactExamples
        }
    }

    private var notesContactExamples: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("On iPhone")
                .font(.caption.weight(.bold))
                .foregroundStyle(OracleTheme.textPrimary)

            InstructionAnnotatedScreenshot(
                imageName: InstructionScreenshotAsset.contactDetailNotes,
                callouts: [
                    InstructionScreenshotCallout(
                        text: "Your prediction appears here.",
                        anchor: CGPoint(x: 0.22, y: 0.82),
                        placement: .above
                    ),
                ]
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
        }
    }

    // MARK: - Chrome

    private var guideHero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Start here")
                .font(.caption.weight(.semibold))
                .foregroundStyle(OracleTheme.gold)
            Text("Use the tabs above — same topics as **Home**. Set up once, then tap **Perform**.")
                .font(.subheadline)
                .foregroundStyle(OracleTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var guideTabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PerformanceGuideTab.allCases) { tab in
                    guideTabChip(tab)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func guideTabChip(_ tab: PerformanceGuideTab) -> some View {
        let selected = selectedTab == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.caption.weight(.semibold))
                Text(tab.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .foregroundStyle(selected ? OracleTheme.textPrimary : OracleTheme.textSecondary)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [tab.tint.opacity(0.38), OracleTheme.deepIndigo.opacity(0.22)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        selected
                            ? LinearGradient(
                                colors: [OracleTheme.gold.opacity(0.85), tab.tint.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(colors: [OracleTheme.cardBorder], startPoint: .top, endPoint: .bottom),
                        lineWidth: selected ? 1.5 : 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var performExitHint: some View {
        Text("Exit Perform anytime: **two-finger swipe down** on the screen.")
            .font(.caption)
            .foregroundStyle(OracleTheme.textSecondary)
            .padding(.top, 4)
    }
}

// MARK: - Tabs

private enum PerformanceGuideTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case song = "Song"
    case callerName = "Caller name"
    case album = "Album"
    case notes = "Notes"

    var id: String { rawValue }

    var title: String { rawValue }

    var icon: String {
        switch self {
        case .overview: return "lightbulb.fill"
        case .song: return "music.note.list"
        case .callerName: return "phone.arrow.down.left.fill"
        case .album: return "photo.on.rectangle.angled"
        case .notes: return "note.text"
        }
    }

    var tint: Color {
        switch self {
        case .overview: return OracleTheme.gold
        case .song: return OracleTheme.indigo
        case .callerName: return OracleTheme.sectionTeal
        case .album: return OracleTheme.sectionSlate
        case .notes: return OracleTheme.sectionTeal
        }
    }
}

/// One-line pointer to Overview contact explainer (contact feature tabs).
private struct GuideContactSetupLink: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "person.crop.circle")
                .font(.caption)
                .foregroundStyle(OracleTheme.gold)
            Text(.init("**Contact setup** (Unknown vs Known, same on all three cards) → **Overview** tab."))
                .font(.footnote)
                .foregroundStyle(OracleTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
        }
    }
}

/// Optional Share / real ringtone — reads current toggle.
private struct PerformanceGuideOptionalShare: View {
    @AppStorage(Prefs.Key.autoShareOnSongLock) private var autoShareOnSongLock = false
    var onOpenFavorites: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            InstructionSection(
                title: "Optional: real ringtone",
                icon: "square.and.arrow.up.fill",
                tint: OracleTheme.indigo,
                lines: PerformInstructionsCopy.optionalRealRingtone(autoShareOn: autoShareOnSongLock)
            )

            ShareRingtoneFavoritesIllustration()
            Button(action: onOpenFavorites) {
                Label("Favorites setup (Use as Ringtone)", systemImage: "star.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .tint(OracleTheme.gold)
        }
    }
}

/// Reusable block for Instructions (same cards as Home sections).
struct InstructionSection: View {
    let title: String
    let icon: String
    let tint: Color
    let lines: [String]

    var body: some View {
        TipCard(title: title, icon: icon, tint: tint, lines: lines)
    }
}

struct InstructionSubsection: View {
    let title: String
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(OracleTheme.textPrimary)
            ForEach(lines, id: \.self) { line in
                if line.isEmpty {
                    Spacer().frame(height: 4)
                } else {
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .foregroundStyle(OracleTheme.textSecondary)
                        Text(.init(line))
                            .font(.footnote)
                            .foregroundStyle(OracleTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
        }
    }
}

/// Legacy embed (e.g. if referenced elsewhere) — slim perform intro only.
struct PerformanceGuideContent: View {
    @AppStorage(Prefs.Key.autoShareOnSongLock) private var autoShareOnSongLock = false
    var onOpenFavorites: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            InstructionSection(
                title: "How the trick works",
                icon: "sparkles",
                tint: OracleTheme.gold,
                lines: PerformInstructionsCopy.howTheTrickWorks
            )
            InstructionSection(
                title: "Performance settings",
                icon: "photo.on.rectangle.angled",
                tint: OracleTheme.gold,
                lines: PerformInstructionsCopy.performanceSettings
            )
            PerformanceGuideOptionalShare(onOpenFavorites: onOpenFavorites)
        }
    }
}
