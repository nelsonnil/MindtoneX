import SwiftUI

/// Compact shortcut status for the main mode cards; full install steps live in sheets.
struct SilentShortcutStatusRow: View {
    let mode: Prefs.PerformanceMode
    @ObservedObject private var shortcut = SilentShortcut.shared
    @AppStorage(SilentShortcut.Key.silentOnEnabled) private var silentOnEnabled = false
    @AppStorage(SilentShortcut.Key.silentOffEnabled) private var silentOffEnabled = false
    var onSetup: () -> Void

    private var enabledForMode: Bool { mode == .fakeRingtone ? silentOnEnabled : silentOffEnabled }
    private var shortcutName: String { mode == .fakeRingtone ? SilentShortcut.silentOnName : SilentShortcut.silentOffName }
    private var label: String {
        mode == .fakeRingtone ? "Auto silent via Shortcut" : "Auto Silent Off via Shortcut"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let hint = shortcut.hint {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(OracleTheme.coral)
                    Text(hint).font(.caption)
                    Spacer(minLength: 0)
                    Button { shortcut.hint = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(OracleTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 10) {
                Circle()
                    .fill(enabledForMode ? Color.green : OracleTheme.textSecondary)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.subheadline.weight(.medium))
                    Text(enabledForMode ? "Perform runs “\(shortcutName)”" : "Shortcut not enabled")
                        .font(.caption)
                        .foregroundStyle(OracleTheme.textSecondary)
                }
                Spacer()
                if !enabledForMode {
                    Button("Setup", action: onSetup)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(OracleTheme.gold)
                } else {
                    Button("Test") { shortcut.test(mode: mode) }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(OracleTheme.textSecondary)
                }
            }
        }
    }
}
