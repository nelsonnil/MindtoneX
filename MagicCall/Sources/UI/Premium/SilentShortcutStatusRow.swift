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
                ShortcutHintBanner(hint: hint) { shortcut.hint = nil }
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

/// Download / install entry point for both Ringtone Oracle Silent shortcuts.
struct ShortcutsInstallPanel: View {
    @ObservedObject private var shortcut = SilentShortcut.shared
    @AppStorage(SilentShortcut.Key.silentOnEnabled) private var silentOnEnabled = false
    @AppStorage(SilentShortcut.Key.silentOffEnabled) private var silentOffEnabled = false
    @Environment(\.openURL) private var openURL
    var onInstallGuide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                OracleEyebrow(text: "Shortcuts")
                Spacer()
                Button(action: onInstallGuide) {
                    Label("Install guide", systemImage: "book.pages")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(OracleTheme.gold)
            }

            if let hint = shortcut.hint {
                ShortcutHintBanner(hint: hint) { shortcut.hint = nil }
            }

            VStack(spacing: 0) {
                shortcutRow(name: SilentShortcut.silentOnName,
                            role: "Used by Fake Ringtone",
                            enabled: silentOnEnabled,
                            installURL: SilentShortcut.silentOnInstallURL)
                Divider().overlay(OracleTheme.cardBorder).padding(.leading, 44)
                shortcutRow(name: SilentShortcut.silentOffName,
                            role: "Used by Share Ringtone",
                            enabled: silentOffEnabled,
                            installURL: SilentShortcut.silentOffInstallURL)
            }
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
            }

            HStack(spacing: 10) {
                if !(silentOnEnabled && silentOffEnabled) {
                    Button("I’ve installed them — turn on") { SilentShortcut.enableBoth() }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(OracleTheme.gold)
                } else {
                    Label("Perform runs Silent Off first", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Spacer()
                    Button("Test") { shortcut.test(mode: .shareRingtone) }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(OracleTheme.textSecondary)
                }
            }
            if let result = shortcut.lastTestResult {
                Text(result).font(.caption2).foregroundStyle(OracleTheme.textSecondary)
            }
        }
    }

    private func shortcutRow(name: String, role: String, enabled: Bool, installURL: URL?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.footnote)
                .foregroundStyle(OracleTheme.gold)
                .frame(width: 28, height: 28)
                .background(OracleTheme.gold.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(OracleTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(enabled ? "\(role) · enabled" : role)
                    .font(.caption2)
                    .foregroundStyle(enabled ? Color.green : OracleTheme.textSecondary)
            }
            Spacer(minLength: 8)
            Button {
                if let installURL {
                    openURL(installURL)
                } else {
                    onInstallGuide()
                }
            } label: {
                Label("Get", systemImage: "arrow.down.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .foregroundStyle(Color(red: 0.12, green: 0.10, blue: 0.05))
                    .background(OracleTheme.goldGradient)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Get \(name)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }
}

struct ShortcutHintBanner: View {
    let hint: String
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(OracleTheme.coral)
            Text(hint).font(.caption)
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(OracleTheme.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(OracleTheme.coral.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
