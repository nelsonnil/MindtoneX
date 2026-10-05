import SwiftUI

/// Unified performance instructions — mode picker + polished guide content.
struct PerformanceGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Prefs.Key.performanceMode) private var performanceModeRaw = Prefs.PerformanceMode.fakeRingtone.rawValue
    @State private var guideMode: Prefs.PerformanceMode
    var onOpenFavorites: () -> Void

    init(initialMode: Prefs.PerformanceMode, onOpenFavorites: @escaping () -> Void) {
        _guideMode = State(initialValue: initialMode)
        self.onOpenFavorites = onOpenFavorites
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Mode", selection: $guideMode) {
                    ForEach(Prefs.PerformanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Group {
                    switch guideMode {
                    case .fakeRingtone:
                        FakeGuideContent(onOpenFavorites: onOpenFavorites)
                    case .shareRingtone:
                        ShareGuideContent(onOpenFavorites: onOpenFavorites)
                    }
                }
                .animation(.easeInOut(duration: 0.22), value: guideMode)

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

struct FakeGuideContent: View {
    var onOpenFavorites: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            guideIntro(
                title: Prefs.PerformanceMode.fakeRingtone.title,
                icon: "bell.slash.fill",
                tint: OracleTheme.gold,
                text: """
                Put your iPhone on Silent. When a real call arrives, the system ringtone stays quiet, but MindtoneX plays your song through the iPhone speaker when iOS allows. When the caller hangs up, playback stops.
                """
            )

            SilentModeIllustration()

            OracleGuideSection(title: "Before you perform", items: [
                "Settings → Apps → Phone → Incoming Calls: Banner",
                "Stay in MindtoneX (screen stays awake while performing)",
            ])

            TipCard(
                title: "Long-press the stage → Share",
                icon: "hand.tap.fill",
                tint: OracleTheme.gold,
                lines: [
                    "Set **Playback volume** on the home card, or use the side volume buttons during Perform.",
                    "After the call **ends**, **press and hold** the stage screen about **half a second** — the Share sheet opens.",
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

struct ShareGuideContent: View {
    @AppStorage(VoiceSettings.Key.inputMode) private var inputModeRaw = VoiceSettings.InputMode.manual.rawValue
    @AppStorage(VoiceSettings.Key.lockDelay) private var lockDelay = VoiceSettings.defaultLockDelay
    var onOpenFavorites: () -> Void

    private var input: VoiceSettings.InputMode {
        VoiceSettings.InputMode(rawValue: inputModeRaw) ?? .manual
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            guideIntro(
                title: Prefs.PerformanceMode.shareRingtone.title,
                icon: "bell.badge.fill",
                tint: OracleTheme.coral,
                text: """
                Sets your song as a real iOS ringtone (Use as Ringtone). Turn Silent OFF and ringer volume up. After setup, one tap in the Share sheet is enough each performance.
                """
            )

            Label("Silent must be OFF in this mode", systemImage: "bell.fill")
                .font(.subheadline.weight(.semibold))
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(OracleTheme.coral.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            FavoritesQuickAccessSection(onOpenFavorites: onOpenFavorites)

            HowItWorksCard(
                title: "How Perform works",
                icon: "list.number",
                steps: PerformCopy.shareSteps(input: input, lockSeconds: Int(lockDelay))
            )

            TipCard(title: "One Home press", icon: "house.fill", tint: OracleTheme.danger, lines: [PerformCopy.shareHomeStep])
            TipCard(title: "Timing", icon: "clock", tint: OracleTheme.coral, lines: PerformCopy.shareTiming(lockSeconds: Int(lockDelay)))
            TipCard(title: "Good to know", icon: "exclamationmark.triangle", tint: .yellow, lines: PerformCopy.shareCaveats)
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

/// One-time Share sheet setup so **Use as Ringtone** stays on the first row (Fake long-press Share and Share mode).
private struct FavoritesQuickAccessSection: View {
    var onOpenFavorites: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TipCard(
                title: "First time: add to Favorites",
                icon: "star.circle.fill",
                tint: OracleTheme.gold,
                lines: [
                    "Do this **once** the first time you see the Share sheet (\(Prefs.PerformanceMode.fakeRingtone.title) after long-press, or \(Prefs.PerformanceMode.shareRingtone.title) Perform).",
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
