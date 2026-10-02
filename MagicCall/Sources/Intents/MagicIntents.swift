import AppIntents

/// Disparadores físicos ocultos: asigna estos atajos a Back Tap
/// (Ajustes › Accesibilidad › Tocar › Toque posterior) o al botón de Acción.
struct PlaySongIntent: AppIntent {
    static let title: LocalizedStringResource = "Sonar canción"
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.trigger(source: "App Intent")
        return .result()
    }
}

struct StopSongIntent: AppIntent {
    static let title: LocalizedStringResource = "Parar canción"
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.silence(reason: "App Intent")
        return .result()
    }
}

struct MagicShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PlaySongIntent(),
                    phrases: ["Sonar canción en \(.applicationName)"],
                    shortTitle: "Sonar canción",
                    systemImageName: "music.note")
        AppShortcut(intent: StopSongIntent(),
                    phrases: ["Parar canción en \(.applicationName)"],
                    shortTitle: "Parar canción",
                    systemImageName: "stop.fill")
    }
}
