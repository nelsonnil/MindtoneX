import SwiftUI

/// Instructions — organized like Home (Performance → Song input → Caller → Notes → Feedback → Library).
struct PerformanceGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onOpenFavorites: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                guideHero

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

                PerformanceGuideOptionalShare(onOpenFavorites: onOpenFavorites)

                InstructionSection(
                    title: "Song",
                    icon: "music.note.list",
                    tint: OracleTheme.indigo,
                    lines: PerformInstructionsCopy.songInputOverview
                )

                InstructionSubsection(title: "Camera (handwriting OCR)", lines: PerformInstructionsCopy.songInputCamera)
                InstructionSubsection(title: "Voice (AI)", lines: PerformInstructionsCopy.songInputVoice(lockSeconds: Int(VoiceSettings.lockDelay)))
                InstructionSubsection(title: "Notes", lines: PerformInstructionsCopy.songInputNotes)
                InstructionSubsection(title: "API", lines: PerformInstructionsCopy.songInputAPI)

                TipCard(
                    title: "Mix song + caller + Notes",
                    icon: "square.stack.3d.up.fill",
                    tint: OracleTheme.sectionTeal,
                    lines: PerformInstructionsCopy.songInputCombinations
                )

                InstructionSection(
                    title: "Caller name",
                    icon: "phone.arrow.down.left.fill",
                    tint: OracleTheme.sectionTeal,
                    lines: PerformInstructionsCopy.callerName
                )

                InstructionSubsection(
                    title: "Known vs Unknown (Contacts)",
                    lines: PerformInstructionsCopy.callerNameKnownUnknown
                )

                InstructionSection(
                    title: "Notes contact",
                    icon: "note.text",
                    tint: OracleTheme.sectionTeal,
                    lines: PerformInstructionsCopy.notesContact
                )

                InstructionSection(
                    title: "Feedback",
                    icon: "eye.fill",
                    tint: OracleHomeSection.feedback.accent,
                    lines: PerformInstructionsCopy.feedback
                )

                InstructionSection(
                    title: "Library",
                    icon: "books.vertical.fill",
                    tint: OracleTheme.textSecondary,
                    lines: PerformInstructionsCopy.library
                )

                InstructionSection(
                    title: "Perform log",
                    icon: "list.bullet.rectangle",
                    tint: OracleTheme.textSecondary,
                    lines: PerformInstructionsCopy.performLog
                )

                Text("Exit Perform anytime: **two-finger swipe down** on the screen.")
                    .font(.caption)
                    .foregroundStyle(OracleTheme.textSecondary)
                    .padding(.top, 4)
            }
            .padding(20)
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

    private var guideHero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Start here")
                .font(.caption.weight(.semibold))
                .foregroundStyle(OracleTheme.gold)
            Text("Everything below matches the **Home** cards: set up once, then tap **Perform**.")
                .font(.subheadline)
                .foregroundStyle(OracleTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
