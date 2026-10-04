import SwiftUI

enum OracleSheet: Identifiable {
    case performanceGuide
    case shortcutsSetup
    case favoritesSetup
    case advanced
    case debugLog
    case apiSettings

    var id: String {
        switch self {
        case .performanceGuide: return "guide"
        case .shortcutsSetup: return "shortcuts"
        case .favoritesSetup: return "favorites"
        case .advanced: return "advanced"
        case .debugLog: return "debugLog"
        case .apiSettings: return "apiSettings"
        }
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

