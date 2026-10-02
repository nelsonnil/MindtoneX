import SwiftUI

/// Setup card: how to install the Silent Mode shortcuts, status, test and last error hint.
struct SilentShortcutCard: View {
    let mode: Prefs.PerformanceMode
    @ObservedObject private var shortcut = SilentShortcut.shared
    @AppStorage(SilentShortcut.Key.silentOnEnabled) private var silentOnEnabled = false
    @AppStorage(SilentShortcut.Key.silentOffEnabled) private var silentOffEnabled = false

    private var enabledForMode: Bool { mode == .fakeRingtone ? silentOnEnabled : silentOffEnabled }
    private var shortcutName: String { mode == .fakeRingtone ? SilentShortcut.silentOnName : SilentShortcut.silentOffName }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let hint = shortcut.hint {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(hint).font(.footnote)
                    Spacer(minLength: 0)
                    Button {
                        shortcut.hint = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            HowItWorksCard(
                title: "Silent Mode shortcuts (one-time setup)",
                icon: "bell.slash.circle",
                steps: [
                    "Open the **Shortcuts** app and tap **+**.",
                    "Add the action **Set Silent Mode** and set it to **On**.",
                    "Name the shortcut exactly **\(SilentShortcut.silentOnName)** and tap **Done**.",
                    "Repeat with Silent Mode **Off** and the name **\(SilentShortcut.silentOffName)**.",
                ],
                footer: "Got a ready-made shortcut file or iCloud link? Open it and tap **Add Shortcut** — keep the name exactly as it is.\n\nWhen you press **Perform**, Shortcuts flashes on screen for a moment, then Ringtone Oracle comes straight back to the black screen. **Press Perform before the spectator is watching.**"
            )

            HStack {
                Label(enabledForMode ? "Perform runs “\(shortcutName)”" : "Shortcut is off for this mode",
                      systemImage: enabledForMode ? "checkmark.circle.fill" : "circle")
                    .font(.footnote)
                    .foregroundStyle(enabledForMode ? .green : .secondary)
                Spacer()
            }
            HStack(spacing: 10) {
                if !(silentOnEnabled && silentOffEnabled) {
                    Button("I’ve installed them — turn on") { SilentShortcut.enableBoth() }
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
