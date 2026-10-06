import SwiftUI

/// Performance instructions — single flow (stage + optional auto-share).
struct PerformanceGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onOpenFavorites: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PerformanceGuideContent(onOpenFavorites: onOpenFavorites)

                TipCard(
                    title: "Missed call & voicemail",
                    icon: "recordingtape",
                    tint: OracleTheme.textSecondary,
                    lines: PerformCopy.voicemailAndMissedCall
                )
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
}

struct PerformanceGuideContent: View {
    @AppStorage(Prefs.Key.autoShareOnSongLock) private var autoShareOnSongLock = false
    var onOpenFavorites: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            guideIntro(
                title: "Performance",
                icon: "theatermasks.fill",
                tint: OracleTheme.gold,
                text: """
                Choose a **stage screenshot** (Home or Lock screen) so Perform looks like your iPhone. When a real call arrives, MindtoneX plays your song through the speaker when iOS allows. When the caller hangs up, playback stops.
                """
            )

            OracleGuideSection(title: "Before you perform", items: [
                "Performance card → **Choose screenshot** (required)",
                "Settings → Apps → Phone → Incoming Calls: Banner",
                "Stay in MindtoneX (screen stays awake while performing)",
            ])

            TipCard(
                title: "Auto-open Share (optional)",
                icon: "square.and.arrow.up.fill",
                tint: OracleTheme.indigo,
                lines: [
                    "Turn on **Auto-open Share when song locks** on the Performance card if you want **Use as Ringtone** as soon as Voice, Notes, or API locks a song during Perform.",
                    autoShareOnSongLock
                        ? "Toggle is **ON** on this device."
                        : "Toggle is **OFF** — you can still long-press the stage after hang-up.",
                ]
            )

            TipCard(
                title: "Long-press the stage → Share",
                icon: "hand.tap.fill",
                tint: OracleTheme.gold,
                lines: [
                    "Set **Playback volume** on the home card, or use the side volume buttons during Perform.",
                    "After the call **ends**, **press and hold** the stage about **half a second** — the Share sheet opens.",
                    "Tap **Use as Ringtone** (pin it to Favorites once — see below — then it is always one tap).",
                    "Only works **after hang-up** — not while the phone is ringing or while the song is still playing.",
                ]
            )

            FavoritesQuickAccessSection(onOpenFavorites: onOpenFavorites)

            TipCard(title: "Timing", icon: "clock", tint: OracleTheme.indigo, lines: PerformCopy.fakeTiming)

            Text("Exit Perform: two-finger swipe down from mid-screen.")
                .font(.caption)
                .foregroundStyle(OracleTheme.textSecondary)
        }
    }
}

private func guideIntro(title: String, icon: String, tint: Color, text: String) -> some View {
    VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(OracleTheme.textPrimary)
        }
        Text(.init(text))
            .font(.subheadline)
            .foregroundStyle(OracleTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.white.opacity(0.06))
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
}

private struct FavoritesQuickAccessSection: View {
    var onOpenFavorites: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TipCard(
                title: "First time: add to Favorites",
                icon: "star.circle.fill",
                tint: OracleTheme.gold,
                lines: [
                    "Do this **once** the first time you see the Share sheet (auto-share or long-press after hang-up).",
                    "Tap **More** (•••) → **Edit Actions** → tap **+** next to **Use as Ringtone** → **Favorites**.",
                    "From then on, **Use as Ringtone** appears on the **top row** — fast access every performance.",
                ]
            )
            ShareRingtoneFavoritesIllustration()
            Button(action: onOpenFavorites) {
                Label("Open step-by-step Favorites guide", systemImage: "book.pages.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .tint(OracleTheme.gold)
        }
    }
}

struct OracleGuideSection: View {
    let title: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OracleTheme.textPrimary)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(OracleTheme.gold)
                        .font(.subheadline)
                        .padding(.top, 1)
                    Text(.init(item))
                        .font(.footnote)
                        .foregroundStyle(OracleTheme.textSecondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
