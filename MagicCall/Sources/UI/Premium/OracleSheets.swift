import SwiftUI

enum OracleSheet: Identifiable {
    case guide
    case fakeDetails
    case shareDetails
    case shortcutsSetup
    case favoritesSetup
    case advanced
    case debugLog
    case voiceSettings
    case voiceDebug

    var id: String {
        switch self {
        case .guide: return "guide"
        case .fakeDetails: return "fake"
        case .shareDetails: return "share"
        case .shortcutsSetup: return "shortcuts"
        case .favoritesSetup: return "favorites"
        case .advanced: return "advanced"
        case .debugLog: return "debugLog"
        case .voiceSettings: return "voiceSettings"
        case .voiceDebug: return "voiceDebug"
        }
    }
}

struct GuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(VoiceSettings.Key.lockDelay) private var lockDelay = VoiceSettings.defaultLockDelay
    @State private var showAdvanced = false

    var body: some View {
        NavigationStack {
            List {
                Section("Modes") {
                    NavigationLink("Fake Ringtone setup") { FakeDetailSheet() }
                    NavigationLink("Share Ringtone setup") { ShareDetailSheet() }
                }
                Section("One-time setup") {
                    NavigationLink("Silent Mode shortcuts") { ShortcutsSetupSheet() }
                    NavigationLink("Share Favorites") { FavoritesSetupSheet() }
                }
                Section("Song input") {
                    NavigationLink("AI Voice & API key") { VoiceSettingsView() }
                }
                Section("Performance") {
                    oracleTextBlock(PerformCopy.fakeTiming)
                    oracleTextBlock(PerformCopy.shareTiming(lockSeconds: Int(lockDelay)))
                }
                Section("Troubleshooting") {
                    Text("If the song doesn’t play, check Silent mode, Focus, Bluetooth, and media volume. Export the debug log from the Advanced card at the bottom of the home screen.")
                        .font(.footnote)
                }
                Section {
                    Button("Advanced settings") { showAdvanced = true }
                }
            }
            .navigationTitle("User Guide")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showAdvanced) {
                NavigationStack { SettingsView() }
            }
        }
    }

    private func oracleTextBlock(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(lines, id: \.self) { line in
                Text(.init("• \(line)"))
                    .font(.footnote)
            }
        }
    }
}

struct FakeDetailSheet: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("""
                Put your iPhone on **Silent**. When a real call arrives, the system ringtone stays quiet, but this app plays your song full volume. When the caller hangs up, the song stops — so it feels like the ringtone was the song all along.
                """)
                .font(.subheadline)

                SilentModeIllustration()

                guideSection("Before you perform", items: [
                    "Silent mode ON (real ringtone muted)",
                    "Settings → Apps → Phone → Incoming Calls: **Banner**",
                    "Silence Unknown Callers: **Off**",
                    "Focus / Do Not Disturb: **Off**",
                    "Bluetooth & AirPods: **Disconnected**",
                    "Media volume: **Up**",
                    "Stay in Ringtone Oracle, screen on & unlocked",
                ])

                TipCard(title: "Performance tip / timing", icon: "clock", tint: OracleTheme.indigo, lines: PerformCopy.fakeTiming)

                Text("On the black screen: stay in this app, keep the phone unlocked. Exit with a **two-finger swipe down** (start mid-screen, not at the top edge). Optional: triple-tap the top-left corner for the debug log.")
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

    private var voice: Bool {
        (VoiceSettings.InputMode(rawValue: inputModeRaw) ?? .manual) == .aiVoice
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
                    steps: PerformCopy.shareSteps(voice: voice, lockSeconds: Int(lockDelay))
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

struct ShortcutsSetupSheet: View {
    @AppStorage(Prefs.Key.performanceMode) private var performanceModeRaw = Prefs.PerformanceMode.fakeRingtone.rawValue

    private var mode: Prefs.PerformanceMode {
        Prefs.PerformanceMode(rawValue: performanceModeRaw) ?? .fakeRingtone
    }

    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Install shortcuts")
                        .font(.subheadline.weight(.semibold))
                    installButton(SilentShortcut.silentOnName, url: SilentShortcut.silentOnInstallURL)
                    installButton(SilentShortcut.silentOffName, url: SilentShortcut.silentOffInstallURL)
                    Button {
                        openURL(SilentShortcut.createShortcutURL)
                    } label: {
                        Label("Open Shortcuts to create them", systemImage: "plus.square.on.square")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(OracleTheme.gold)
                }
                .padding(14)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                SilentShortcutCard(mode: mode)
            }
            .padding()
        }
        .background(OracleTheme.bgTop)
        .navigationTitle("Shortcuts setup")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func installButton(_ name: String, url: URL?) -> some View {
        if let url {
            Button {
                openURL(url)
            } label: {
                Label("Add “\(name)”", systemImage: "arrow.down.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(OracleTheme.gold)
            .foregroundStyle(Color(red: 0.12, green: 0.10, blue: 0.05))
        } else {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundStyle(OracleTheme.gold)
                    .font(.caption)
                    .padding(.top, 2)
                Text("**\(name)** — create it in Shortcuts with the steps below (one-tap download link coming soon).")
                    .font(.footnote)
            }
        }
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
