import SwiftUI

enum OracleSheet: Identifiable {
    case fakeDetails
    case shareDetails
    case shortcutsSetup
    case favoritesSetup
    case advanced
    case debugLog
    case apiSettings

    var id: String {
        switch self {
        case .fakeDetails: return "fake"
        case .shareDetails: return "share"
        case .shortcutsSetup: return "shortcuts"
        case .favoritesSetup: return "favorites"
        case .advanced: return "advanced"
        case .debugLog: return "debugLog"
        case .apiSettings: return "apiSettings"
        }
    }
}

struct FakeDetailSheet: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("""
                Put your iPhone on **Silent**. When a real call arrives, the system ringtone stays quiet, but this app plays your song full volume through the **iPhone speaker** when iOS allows. When the caller hangs up, the song stops — so it feels like the ringtone was the song all along.

                Some Bluetooth devices (e.g. **Meta glasses**) may still take audio on certain iOS versions — disconnect them if the song sounds wrong or too quiet.
                """)
                .font(.subheadline)

                SilentModeIllustration()

                guideSection("Before you perform", items: [
                    "Settings → Apps → Phone → Incoming Calls: **Banner**",
                    "Stay in RingtoneX (display stays on while performing)",
                ])

                TipCard(title: "Performance tip / timing", icon: "clock", tint: OracleTheme.indigo, lines: PerformCopy.fakeTiming)

                Text("On the black screen: stay in this app — the display won’t auto-lock while RingtoneX is open. Exit with a **two-finger swipe down** (start mid-screen, not at the top edge). Optional: triple-tap the top-left corner for the debug log.")
                    .font(.caption)
                    .foregroundStyle(OracleTheme.textSecondary)
            }
            .padding()
        }
        .background(OracleTheme.bgTop)
        .navigationTitle("Fake Ringtone")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ShareDetailSheet: View {
    @AppStorage(VoiceSettings.Key.inputMode) private var inputModeRaw = VoiceSettings.InputMode.manual.rawValue
    @AppStorage(VoiceSettings.Key.lockDelay) private var lockDelay = VoiceSettings.defaultLockDelay

    private var input: VoiceSettings.InputMode {
        VoiceSettings.InputMode(rawValue: inputModeRaw) ?? .manual
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("Silent must be OFF in this mode", systemImage: "bell.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(OracleTheme.coral.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text("""
                This sets your song as a **real iOS ringtone** (official “Use as Ringtone”). Turn **Silent OFF** and turn **ringer volume up**. After setup, one tap in the Share sheet is enough each performance.
                """)
                .font(.subheadline)

                ShareRingtoneFavoritesIllustration()

                HowItWorksCard(
                    title: "How Share Ringtone Perform works",
                    icon: "list.number",
                    steps: PerformCopy.shareSteps(input: input, lockSeconds: Int(lockDelay))
                )

                TipCard(title: "Performance tip: one Home press", icon: "house.fill", tint: OracleTheme.danger,
                        lines: [PerformCopy.shareHomeStep])

                TipCard(title: "Performance tip / timing", icon: "clock", tint: OracleTheme.coral,
                        lines: PerformCopy.shareTiming(lockSeconds: Int(lockDelay)))

                TipCard(title: "Good to know", icon: "exclamationmark.triangle", tint: .yellow,
                        lines: PerformCopy.shareCaveats)
            }
            .padding()
        }
        .background(OracleTheme.bgTop)
        .navigationTitle("Share Ringtone")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Manual steps only — download lives on the mode card (Get).
struct ManualShortcutStepsSheet: View {
    let mode: Prefs.PerformanceMode

    var body: some View {
        ScrollView {
            SilentShortcutCard(mode: mode, manualStepsOnly: true)
                .padding()
        }
        .background(OracleTheme.bgTop)
        .navigationTitle("Build shortcut")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ShortcutsSetupSheet: View {
    @AppStorage(Prefs.Key.performanceMode) private var performanceModeRaw = Prefs.PerformanceMode.fakeRingtone.rawValue

    private var mode: Prefs.PerformanceMode {
        Prefs.PerformanceMode(rawValue: performanceModeRaw) ?? .fakeRingtone
    }

    var body: some View {
        ManualShortcutStepsSheet(mode: mode)
    }
}

struct FavoritesSetupSheet: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ShareRingtoneFavoritesIllustration()
                Text("In the Share sheet, tap **More** → **Edit Actions** → tap **+** on **Use as Ringtone** → **Favorites**. Then **Use as Ringtone** appears on the first row every time.")
                    .font(.footnote)
            }
            .padding()
        }
        .background(OracleTheme.bgTop)
        .navigationTitle("Favorites")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private func guideSection(_ title: String, items: [String]) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        Text(title)
            .font(.subheadline.weight(.semibold))
        ForEach(items, id: \.self) { item in
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(OracleTheme.gold)
                    .font(.caption)
                    .padding(.top, 2)
                Text(.init(item))
                    .font(.footnote)
            }
        }
    }
    .padding(14)
    .background(Color.white.opacity(0.06))
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
}
