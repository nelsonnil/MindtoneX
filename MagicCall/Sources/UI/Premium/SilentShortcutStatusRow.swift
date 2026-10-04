import SwiftUI

/// Download / install for the one Silent shortcut this mode needs (Fake → Silent On, Share → Silent Off).
struct ShortcutsInstallPanel: View {
    let mode: Prefs.PerformanceMode
    @ObservedObject private var shortcut = SilentShortcut.shared
    @AppStorage(SilentShortcut.Key.silentOnEnabled) private var silentOnEnabled = false
    @AppStorage(SilentShortcut.Key.silentOffEnabled) private var silentOffEnabled = false
    @Environment(\.openURL) private var openURL
    @State private var showManualSteps = false

    private var isFake: Bool { mode == .fakeRingtone }
    private var enabled: Bool { isFake ? silentOnEnabled : silentOffEnabled }
    private var shortcutName: String { isFake ? SilentShortcut.silentOnName : SilentShortcut.silentOffName }
    private var installURL: URL? { isFake ? SilentShortcut.silentOnInstallURL : SilentShortcut.silentOffInstallURL }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let hint = shortcut.hint {
                ShortcutHintBanner(hint: hint) { shortcut.hint = nil }
            }

            shortcutRow

            HStack(alignment: .center, spacing: 12) {
                Text("Run shortcut before Perform")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(OracleTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Toggle("", isOn: autoRunBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(OracleTheme.gold)
                    .fixedSize()
            }
            .padding(.vertical, 4)
            .padding(.trailing, 2)

            HStack(spacing: 10) {
                if enabled {
                    Label("Enabled for Perform", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Spacer()
                Button("Test") { shortcut.test(mode: mode) }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OracleTheme.textSecondary)
                    .disabled(!enabled)
            }
            if let result = shortcut.lastTestResult {
                Text(result).font(.caption2).foregroundStyle(OracleTheme.textSecondary)
            }

            if installURL != nil {
                Button("Build the shortcut yourself instead") { showManualSteps = true }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OracleTheme.gold)
            }
        }
        .sheet(isPresented: $showManualSteps) {
            NavigationStack {
                ManualShortcutStepsSheet(mode: mode)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showManualSteps = false }
                        }
                    }
            }
        }
    }

    private var autoRunBinding: Binding<Bool> {
        Binding(
            get: { enabled },
            set: { newValue in
                if isFake { silentOnEnabled = newValue } else { silentOffEnabled = newValue }
            }
        )
    }

    private var shortcutRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.footnote)
                .foregroundStyle(OracleTheme.gold)
                .frame(width: 28, height: 28)
                .background(OracleTheme.gold.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(shortcutName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(OracleTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(isFake ? "Silent ON for Fake Ringtone" : "Silent OFF for Share Ringtone")
                    .font(.caption2)
                    .foregroundStyle(OracleTheme.textSecondary)
            }
            Spacer(minLength: 8)
            Button(action: getTapped) {
                Label(installURL == nil ? "Manual" : "Get", systemImage: installURL == nil ? "book.pages" : "arrow.down.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .foregroundStyle(Color(red: 0.12, green: 0.10, blue: 0.05))
                    .background(OracleTheme.goldGradient)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(installURL == nil ? "Manual shortcut steps" : "Download \(shortcutName)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
        }
    }

    private func getTapped() {
        if let installURL {
            openURL(installURL)
        } else {
            showManualSteps = true
        }
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
