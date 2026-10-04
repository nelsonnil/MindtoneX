import SwiftUI

/// Manual shortcut steps (and optional test controls when not `manualStepsOnly`).
struct SilentShortcutCard: View {
    let mode: Prefs.PerformanceMode
    var manualStepsOnly = false
    @ObservedObject private var shortcut = SilentShortcut.shared
    @AppStorage(SilentShortcut.Key.silentOnEnabled) private var silentOnEnabled = false
    @AppStorage(SilentShortcut.Key.silentOffEnabled) private var silentOffEnabled = false

    private var enabledForMode: Bool { mode == .fakeRingtone ? silentOnEnabled : silentOffEnabled }
    private var shortcutName: String { mode == .fakeRingtone ? SilentShortcut.silentOnName : SilentShortcut.silentOffName }

    private var steps: [String] {
        if mode == .fakeRingtone {
            return [
                "Open the **Shortcuts** app and tap **+**.",
                "Add **Set Silent Mode** and set it to **On**.",
                "Name the shortcut exactly **\(SilentShortcut.silentOnName)** and tap **Done**.",
                "Keep the shortcut to **one action** (Set Silent Mode). You do **not** need “Open App” for Perform — the app calls Shortcuts with a return URL.",
                "Optional: add **Open App → MindtoneX** at the end only if you run the shortcut by hand from the Shortcuts app.",
            ]
        }
        return [
            "Open the **Shortcuts** app and tap **+**.",
            "Add **Set Silent Mode** and set it to **Off**.",
            "Name the shortcut exactly **\(SilentShortcut.silentOffName)** and tap **Done**.",
            "Keep the shortcut to **one action** (Set Silent Mode). You do **not** need “Open App” for Perform — the app calls Shortcuts with a return URL.",
            "Optional: add **Open App → MindtoneX** at the end only if you run the shortcut by hand from the Shortcuts app.",
        ]
    }

    private var footer: String {
        let silent = mode == .fakeRingtone ? "ON" : "OFF"
        return """
        Got an iCloud link from us? Tap **Get** on the main screen and **Add Shortcut** — keep the name exactly as shown.

        **Manual:** flip Silent \(silent) yourself before each show.

        **Automatic:** turn on **Run shortcut before Perform** on the main screen — Perform opens Shortcuts briefly, sets Silent \(silent), then returns here. Press Perform before you begin the performance.
        """
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let hint = shortcut.hint {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(hint).font(.footnote)
                    Spacer(minLength: 0)
                    Button { shortcut.hint = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            HowItWorksCard(
                title: shortcutName,
                icon: "bell.slash.circle",
                steps: steps,
                footer: footer
            )

            if !manualStepsOnly {
                HStack {
                    Label(enabledForMode ? "Perform runs “\(shortcutName)”" : "Shortcut is off for this mode",
                          systemImage: enabledForMode ? "checkmark.circle.fill" : "circle")
                        .font(.footnote)
                        .foregroundStyle(enabledForMode ? .green : .secondary)
                    Spacer()
                }
                HStack(spacing: 10) {
                    if !enabledForMode {
                        Button("Turn on for Perform") {
                            if mode == .fakeRingtone { silentOnEnabled = true } else { silentOffEnabled = true }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Button("Test") { shortcut.test(mode: mode) }
                        .buttonStyle(.bordered)
                }
                if let result = shortcut.lastTestResult {
                    Text(result).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
